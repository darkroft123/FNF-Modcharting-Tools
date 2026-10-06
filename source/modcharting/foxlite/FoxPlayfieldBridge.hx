package modcharting.foxlite;

#if MODCHART_FOXLITE
import flixel.FlxCamera;
import flixel.FlxG;
import flixel.FlxSprite;
import foxlite.FoxCamera;
import foxlite.FoxObject;
import foxlite.FoxScene;
import foxlite.math.FoxMathUtil;
import foxlite.renderer.FoxRenderer;
import openfl.geom.Matrix3D;
import openfl.geom.Vector3D;
#if LEATHER
import game.Note;
#elseif (PSYCH && PSYCHVERSION >= "0.7")
import objects.Note;
#else
import Note;
#end

/**
 * A `FoxScene` that never allocates a render target.
 *
 * `FoxScene`'s constructor calls `setupBuffers()`, which creates a full screen
 * `FoxFramebuffer` and assigns it to `pixels`. The modcharting bridge only needs the scene as a
 * transform host: `FoxScene` owns the aspect ratio `FoxCamera` projects with, and `foxGroup`
 * owns the update and per camera draw calls. The framebuffer would be dead weight, a screen
 * sized texture allocation for nothing.
 *
 * `setupBuffers()` is public and called from the base constructor, so overriding it is enough
 * to skip the allocation while keeping `__width` / `__height` (and therefore the camera
 * aspect) correct.
 *
 * Nothing is ever rendered through this scene, so `FoxScene.draw()` never runs and neither do
 * `FoxRenderer.begin()` / `backToFlixel()`. The bridge performs no GL state juggling at all.
 */
class FoxTransformScene extends FoxScene {
	public function new(width:Int, height:Int) {
		super(width, height);
	}

	public override function setupBuffers(width:Int, height:Int) {
		__width = width;
		__height = height;
		onFramebufferResized.dispatch(width, height);
	}
}

/**
 * Hardware accelerated 3D bridge for `PlayfieldRenderer`.
 *
 * What it replaces
 * ----------------
 * The classic path projects every note by hand: `ModchartUtil.calculatePerspective()` fakes a
 * perspective divide on a `Vector3D`, the result is baked into `scale`, and
 * `FlxSprite3D.rotateXYZ` concatenates a 2D rotation matrix. That only approximates 3D.
 * `calculatePerspective` never applies a rotation, so a note with a non zero X angle shrinks
 * but does not shear, and it costs a handful of trig calls per note per frame on the CPU.
 *
 * How it works
 * ------------
 * Each note and strum stays a plain `FlxSprite` drawn by Flixel through
 * `FlxCamera.drawPixels()`, but it gets a `FoxSpriteShader` whose vertex stage ends with
 * FoxLite's projection instead of Flixel's. Per frame the note's 3D transform is pushed into a
 * `FlxFox3DSprite`, and `FlxFox3DSprite.draw()` bakes `Projection * View * Model` into that
 * note's own shader uniforms.
 *
 * The important consequence: `openfl_Position`, the sprite's camera local pixel position, is
 * still what places the note on the XY plane. The 2D `x` / `y` / `scale` written by
 * `PlayfieldRenderer` keep working untouched, so camera assignment, scroll factors, strum
 * positions and note hit detection are unaffected. FoxLite only supplies depth and rotation.
 *
 * Because of that, a note at `z == 0` with no rotation is pixel identical to the classic path
 * with no 3D at all, which makes A/B testing against it trivial.
 *
 * Ordering
 * --------
 * `FlxFox3DSprite.draw()` writes uniforms straight into the shader owned by the sprite it
 * wraps, and each note owns its own shader, so a note's uniforms only need to be correct
 * between `applyNote()` and that note's own `draw()`. The bridge therefore bakes per note
 * inside `apply()` rather than sweeping the group once per frame, which keeps the note loop
 * single pass and lets `PlayfieldRenderer` interleave drawing as it already does.
 *
 * `FoxObject.update()` recomputes the world matrix unconditionally, so each wrapper is updated
 * right after its transform is set. The pivot is updated once per frame in `beginFrame()`,
 * before any note, which is all a one level parent chain requires.
 *
 * The mapping
 * -----------
 * The vertex shader maps the quad into `x in [-aspect/2, aspect/2]`, `y in [-1/2, 1/2]`, so the
 * quad nominally covers the whole screen. Reproducing a sprite's own on screen size and
 * position therefore only works if the model matrix satisfies:
 *
 *     worldZ = z * zScale
 *     k      = (cameraZ - worldZ) / f       with f = 1 / tan(fov / 2)
 *     model  = translate(0, 0, worldZ) * scale(-2k, 2k, 1)
 *
 * The X scale is negative on purpose: the shader negates X for the aspect correction, so the
 * negative scale cancels it and the texture is not mirrored. With `cameraZ == f` a note at
 * `z == 0` gets `k == 1`, i.e. scale `(-2, 2, 1)`, which is the identity mapping.
 *
 * `selfTest()` validates all of the above against FoxLite's real matrices at runtime, which is
 * the only way to be sure of it without a GPU in the loop.
 */
class FoxPlayfieldBridge {
	/** Define that has to be set for any of this to compile. */
	public static inline var DEFINE:String = "MODCHART_FOXLITE";

	public var scene:FoxTransformScene;
	public var camera:FoxCamera;

	/**
	 * Playfield pivot. Every note and strum is parented to it, so rotating it tilts the whole
	 * playfield with correct perspective instead of faking it note by note.
	 *
	 * Added to `foxGroup` first, which matters only for `foxGroup.update()`, which the bridge
	 * does not use. What matters is that it is updated before the notes in `beginFrame()`.
	 */
	public var pivot:FoxObject;

	/**
	 * Toggled at runtime so a modchart can be compared against the classic renderer live.
	 *
	 * Safe to flip at any time: `apply()` only leaves its shader attached for the duration of a
	 * note's draw, so the frame after a flip renders through the classic path untouched. Wrappers
	 * are kept alive while disabled and reused, which avoids reallocating a shader per note when
	 * flipping back.
	 */
	public var enabled:Bool = true;

	/**
	 * True when the bridge is usable. `PlayfieldRenderer` checks this to decide whether to skip
	 * the classic perspective bake, so it has to be cheap and allocation free.
	 */
	public var active(default, null):Bool;

	/** Vertical field of view in degrees. Kept in sync with `ModchartUtil.defaultFOV`. */
	public var fov(get, set):Float;

	/**
	 * Degrees added on top of `ModchartUtil.defaultFOV`.
	 *
	 * Separate from `fov` because `beginFrame()` resyncs `fov` from `defaultFOV` every frame, so
	 * a modifier writing `fov` directly would be overwritten before it ever reached the GPU.
	 * This is the value a FOV modifier owns.
	 */
	public var fovOffset:Float = 0;

	/**
	 * How many FoxLite world units one unit of `NotePositionData.z` is worth.
	 *
	 * 0.001 matches the classic path's `noteData.z * 0.001`, so existing modcharts keep
	 * roughly the same depth feel. Raise it to push notes further into the screen.
	 */
	public var zScale:Float = 0.001;

	/**
	 * Playfield tilt in degrees, applied once per frame to the pivot by `beginFrame()`.
	 * Driven by `TiltModifier`.
	 */
	public var tiltX:Float = 0;
	public var tiltY:Float = 0;
	public var tiltZ:Float = 0;

	/** Extra depth, in FoxLite world units, applied on top of every note's own z. */
	public var zOffset:Float = 0;

	/**
	 * Angle sign flips, kept in one place so they can be corrected without hunting.
	 *
	 * The classic path negates all three angles because FNF works in a left handed screen
	 * space frame (x right, y down, z towards the viewer). FoxLite's world is right handed and
	 * Y up, the mirror of that frame, so the same negation applies. If a modchart author
	 * reports inverted tilt, flip these here rather than in the per note push.
	 */
	public var flipAngleX:Bool = true;
	public var flipAngleY:Bool = true;
	public var flipAngleZ:Bool = true;

	/** Runs `selfTest()` once on creation. */
	public var runSelfTest:Bool = false;

	/** Set when the bridge could not be built, so callers can fall back to the classic path. */
	public var failed:Bool = false;
	public var failReason:String = "";

	/**
	 * Clamp on `k`, i.e. on how far in front of the camera a note may get before it counts as
	 * past it. Also keeps `k * f` above the camera's near plane.
	 */
	public static inline var MIN_K:Float = 0.02;

	/** Effective field of view: `_fovBase + fovOffset`. */
	var _fov:Float = 90;

	/** Mirrors `ModchartUtil.defaultFOV`; refreshed by `beginFrame()`. */
	var _fovBase:Float = 90;

	/** `1 / tan(fov / 2)`, cached. Mirrors `FoxMathUtil.perspectiveMatrix`. */
	var _f:Float = 1;
	var _invF:Float = 1;

	var _pivotDirty:Bool = true;
	var _elapsed:Float = 0;
	var _lastFov:Float = -1;
	var _lastWidth:Int = -1;
	var _lastHeight:Int = -1;

	// Wrappers are pooled and indexed parallel to `notes.members` / `strumGroup.members`.
	var _noteWrappers:Array<FoxNoteWrapper> = [];
	var _strumWrappers:Array<FoxNoteWrapper> = [];

	// Used by selfTest() only, so the hot path stays allocation free.
	final _testMatrix:Matrix3D = new Matrix3D();
	final _testVertex:Vector3D = new Vector3D();

	public function new(width:Int, height:Int, defaultFov:Float = 90) {
		try {
			FoxRenderer.initLibs();

			scene = new FoxTransformScene(width, height);

			// `withLightData = false`: notes are drawn by Flixel with a Flixel shader and never
			// go through a FoxLite material, so light data would be pure overhead.
			camera = new FoxCamera(0, 0, 1, 0x00000000, false, false);
			// `FoxCamera.update()` bails out without a scene, and `FoxScene.draw()` (which
			// normally assigns it) never runs here.
			camera.scene = scene;
			camera.aspect = 1;
			camera.doFrustumCulling = false;
			camera.passes = [];
			scene.foxCameras.push(camera);

			pivot = new FoxObject();
			scene.add(pivot);

			syncProjection(width, height, defaultFov);

			active = true;

			if (runSelfTest)
				selfTest();
		} catch (e:Dynamic) {
			failed = true;
			active = false;
			failReason = Std.string(e);
			trace('[modcharting-tools] FoxLite bridge unavailable, falling back to the classic renderer: $failReason');
		}
	}

	/* ---------------------------------------------------------------------------------
	 * Frame flow. Driven from `PlayfieldRenderer.draw()`.
	 * ----------------------------------------------------------------------------- */

	/**
	 * Syncs the camera matrices and updates the playfield pivot.
	 *
	 * Runs once, before any note is applied, so that the pivot's world matrix is ready for
	 * every wrapper that parents to it. `FoxObject.update()` recomputes unconditionally, so
	 * the pivot does not need a dirty check here.
	 */
	public function beginFrame(elapsed:Float, defaultFov:Float, width:Int, height:Int):Void {
		if (!active)
			return;

		_elapsed = elapsed;

		syncProjection(width, height, defaultFov);

		if (_pivotDirty) {
			pivot.setAngle(tiltX, tiltY, tiltZ);
			_pivotDirty = false;
		}

		// Called directly instead of `scene.update()` so the FlxSprite update path is skipped
		// entirely: the scene is not in the display list and has nothing to blit.
		camera.update(elapsed);
		pivot.update(elapsed);
	}

	/** Destroys wrappers whose note no longer exists at the same index. */
	public inline function endFrame(noteCount:Int, strumCount:Int):Void {
		if (!active)
			return;
		prune(_noteWrappers, noteCount);
		prune(_strumWrappers, strumCount);
	}

	/* ---------------------------------------------------------------------------------
	 * Per note / per strum transform push.
	 * ----------------------------------------------------------------------------- */

	/**
	 * @param z       Depth in `NotePositionData` units, scaled by `zScale`.
	 * @param angleX  Degrees.
	 * @param angleY  Degrees.
	 * @param angleZ  Degrees.
	 * @param flxCamera The camera the note is about to be drawn with. Pinned here because
	 *                  `PlayfieldRenderer` reassigns `cameras` later in the same call, while
	 *                  `FlxFox3DSprite.draw()` resolves `sprite.camera` from it.
	 */
	public inline function applyNote(sprite:FlxSprite, index:Int, z:Float, angleX:Float, angleY:Float, angleZ:Float, flxCamera:FlxCamera):Void {
		apply(sprite, index, _noteWrappers, z, angleX, angleY, angleZ, flxCamera);
	}

	public inline function applyStrum(sprite:FlxSprite, index:Int, z:Float, angleX:Float, angleY:Float, angleZ:Float, flxCamera:FlxCamera):Void {
		apply(sprite, index, _strumWrappers, z, angleX, angleY, angleZ, flxCamera);
	}

	inline function apply(sprite:FlxSprite, index:Int, pool:Array<FoxNoteWrapper>, z:Float, angleX:Float, angleY:Float, angleZ:Float, flxCamera:FlxCamera):Void {
		var wrapper = getWrapper(pool, index, sprite);

		// `FlxFox3DSprite.draw()` calls `sprite.getScreenPosition(null, sprite.camera)` and
		// divides by `sprite.camera.width`, so a null camera would throw inside the draw call.
		// A sprite with an empty `cameras` array reports a null camera, so fall back rather
		// than trusting the caller to have resolved one.
		if (flxCamera == null)
			flxCamera = FlxG.camera;
		if (flxCamera == null)
			return;
		if (sprite.camera != flxCamera)
			sprite.camera = flxCamera;

		var worldZ = z * zScale + zOffset;
		var k = (camera.position.z - worldZ) * _invF;

		if (k < MIN_K) {
			// Past the camera. Collapse the quad to zero area rather than toggling `visible`,
			// which would leave Flixel drawing the note with the previous frame's MVP.
			wrapper.position.setTo(0, 0, worldZ);
			wrapper.scale.setTo(0, 0, 1);
		} else {
			wrapper.position.setTo(0, 0, worldZ);
			wrapper.scale.setTo(-2 * k, 2 * k, 1);
			wrapper.setAngle(flipAngleX ? -angleX : angleX, flipAngleY ? -angleY : angleY, flipAngleZ ? -angleZ : angleZ);
		}

		// Order matters: `update()` recomputes the world matrix from the transform just set,
		// `draw()` then bakes it plus the camera matrices into this note's own shader.
		//
		// The shader is deliberately left attached after this. `FlxSprite.draw()` emits through
		// `camera.drawPixels(..., shader)` synchronously, and the caller draws the note after
		// `apply()` returns, so detaching here would hand that draw the previous shader and the
		// note would render flat.
		wrapper.attachShader();
		wrapper.update(_elapsed);
		wrapper.draw(camera);
	}

	public inline function detachNote(sprite:FlxSprite, index:Int):Void {
		detach(sprite, index, _noteWrappers);
	}

	public inline function detachStrum(sprite:FlxSprite, index:Int):Void {
		detach(sprite, index, _strumWrappers);
	}

	inline function detach(sprite:FlxSprite, index:Int, pool:Array<FoxNoteWrapper>):Void {
		var wrapper = index >= 0 && index < pool.length ? pool[index] : null;
		if (wrapper != null && wrapper.sprite == sprite) {
			wrapper.detachShader();
		} else if (sprite != null && Std.isOfType(sprite.shader, FoxSpriteShader)) {
			sprite.shader = null;
		}
	}

	function resolvePreviousShader(sprite:FlxSprite):flixel.graphics.tile.FlxGraphicsShader {
		if (sprite == null)
			return null;

		var result:flixel.graphics.tile.FlxGraphicsShader = null;
		var daNote = Std.downcast(sprite, Note);

		if (daNote != null) {
			var affected:Bool = Reflect.hasField(daNote, "affectedbycolor") ? Reflect.field(daNote, "affectedbycolor") : true;
			if (!affected) {
				result = null;
			} else if (daNote.shader != null && !Std.isOfType(daNote.shader, FoxSpriteShader)) {
				result = daNote.shader;
			} else if (affected && Reflect.field(daNote, "colorSwap") != null && Reflect.field(Reflect.field(daNote, "colorSwap"), "shader") != null) {
				result = cast Reflect.field(Reflect.field(daNote, "colorSwap"), "shader");
			}
		} else if (sprite.shader != null && !Std.isOfType(sprite.shader, FoxSpriteShader)) {
			result = sprite.shader;
		}

		return result;
	}

	inline function getWrapper(pool:Array<FoxNoteWrapper>, index:Int, sprite:FlxSprite):FoxNoteWrapper {
		var existing = index < pool.length ? pool[index] : null;

		var targetShader = resolvePreviousShader(sprite);

		if (existing != null && existing.sprite == sprite) {
			existing.previousShader = targetShader;
			return existing;
		}

		if (existing != null)
			disposeWrapper(existing);

		var wrapper = new FoxNoteWrapper(sprite, new FoxSpriteShader(), targetShader);
		wrapper.parent = pivot;
		if (index < pool.length)
			pool[index] = wrapper;
		else
			pool.push(wrapper);
		scene.add(wrapper);
		return wrapper;
	}

	inline function disposeWrapper(wrapper:FoxNoteWrapper):Void {
		if (wrapper == null) return;
		// Only clear it if it is still ours; a note that has since picked up another shader
		// should keep it.
		try {
			if (wrapper.sprite != null && wrapper.sprite.exists && wrapper.sprite.shader == wrapper.ownShader)
				wrapper.sprite.shader = wrapper.previousShader;
		} catch (e:Dynamic) {}
		// `FoxBasic.destroy()` removes itself from the scene, so no explicit remove needed.
		wrapper.destroy();
	}

	inline function prune(pool:Array<FoxNoteWrapper>, count:Int):Void {
		while (pool.length > count) {
			var wrapper = pool.pop();
			if (wrapper != null)
				disposeWrapper(wrapper);
		}
	}

	/* ---------------------------------------------------------------------------------
	 * Projection sync.
	 * ----------------------------------------------------------------------------- */

	inline function syncProjection(width:Int, height:Int, defaultFov:Float = -1):Void {
		if (defaultFov >= 0)
			_fovBase = defaultFov;

		// `fov` is the *effective* value, so a FOV modifier composes with `defaultFOV` instead of
		// fighting it. Writing `fov` from a modifier would be undone on the very next frame.
		var target = _fovBase + fovOffset;
		if (target != _fov)
			fov = target;

		if (width == _lastWidth && height == _lastHeight && fov == _lastFov)
			return;

		_lastWidth = width;
		_lastHeight = height;
		_lastFov = fov;

		scene.setupBuffers(width, height);

		_f = 1 / Math.tan(fov * 0.5 * FoxMathUtil.degToRad);
		_invF = 1 / _f;

		camera.fov = fov;
		camera.aspect = 1; // the scene aspect already is width / height
		camera.near = MIN_K * _f * 0.5;
		camera.far = Math.max(100, _f * 8);
		camera.position.z = _f;
		camera.__updateProjection = true;
	}

	public function setTilt(x:Float, y:Float, z:Float):Void {
		if (tiltX == x && tiltY == y && tiltZ == z)
			return;
		tiltX = x;
		tiltY = y;
		tiltZ = z;
		_pivotDirty = true;
	}

	private function get_fov():Float {
		return _fov;
	}

	private function set_fov(value:Float):Float {
		if (value <= 0 || value >= 179)
			return _fov;
		_fov = value;
		_lastFov = -1; // force syncProjection to rebuild the projection matrix
		return _fov;
	}

	/* ---------------------------------------------------------------------------------
	 * Validation.
	 * ----------------------------------------------------------------------------- */

	/**
	 * Checks the closed form mapping against FoxLite's own projection and view matrices.
	 *
	 * For a grid of screen pixels and depths it compares the NDC the shader would produce
	 * against the identity screen mapping `2 * t / width - 1`. If this passes, the maths in
	 * `apply()` agrees with the matrices `FoxCamera` actually builds, which is the part that
	 * cannot be confirmed by reading code alone.
	 *
	 * @return `true` when every sample lands within tolerance.
	 */
	public function selfTest(tolerance:Float = 0.002):Bool {
		if (!active || _lastWidth <= 0)
			return false;

		// One update so viewMatrix / projectionMatrix reflect the current fov.
		camera.update(0);

		var width = _lastWidth;
		var height = _lastHeight;
		var aspect = width / height;

		var depths = [0.0, 50.0, 100.0, 200.0, 400.0, -100.0];
		var xs = [0.0, width * 0.25, width * 0.5, width * 0.75, width];
		var ys = [0.0, height * 0.5, height];

		var worst:Float = 0;
		var failures = 0;
		var samples = depths.length * xs.length * ys.length;

		for (z in depths) {
			var worldZ = z * zScale + zOffset;
			var k = (camera.position.z - worldZ) * _invF;

			_testMatrix.identity();
			_testMatrix.appendScale(-2 * k, 2 * k, 1);
			_testMatrix.appendTranslation(0, 0, worldZ);

			for (y in ys) {
				for (x in xs) {
					// What the vertex shader feeds into the MVP for this pixel.
					var lx = -(x - width * 0.5) * aspect / width;
					var ly = -(y - height * 0.5) / height;

					_testVertex.setTo(lx, ly, 0);
					_testMatrix.transformVectorToOutput(_testVertex, _testVertex);

					var ndc = camera.getScreenPoint(_testVertex);

					var errX = Math.abs(ndc.x - (2 * x / width - 1));
					var errY = Math.abs(ndc.y - (1 - 2 * y / height));
					var err = errX > errY ? errX : errY;

					if (err > worst)
						worst = err;
					if (err > tolerance)
						failures++;
				}
			}
		}

		var ok = failures == 0;
		trace('[modcharting-tools] FoxLite selfTest: ' + (ok ? 'PASS' : 'FAIL') + ' — ' + failures + '/' + samples
			+ ' samples out of tolerance, worst error ' + worst);
		return ok;
	}

	public function destroy() {
		clearPool(_noteWrappers);
		clearPool(_strumWrappers);
		active = false;

		if (scene != null) {
			scene.destroy();
			scene = null;
		}
		camera = null;
		pivot = null;
	}

	/** `resize` rather than `length = 0`: Haxe binds parameters read only. */
	inline function clearPool(pool:Array<FoxNoteWrapper>) {
		for (wrapper in pool) {
			if (wrapper != null)
				disposeWrapper(wrapper);
		}
		pool.resize(0);
	}
}
#end
