package modcharting;

import flixel.tweens.FlxEase;
import flixel.math.FlxMath;
import flixel.math.FlxAngle;
import openfl.geom.Vector3D;
import flixel.FlxG;
#if LEATHER
import states.PlayState;
import game.Note;
import game.Conductor;
#elseif (PSYCH && PSYCHVERSION >= "0.7")
import states.PlayState;
import objects.Note;
#else
import PlayState;
import Note;
#end

using StringTools;

class ModchartUtil {
	public static inline function getDownscroll(instance:ModchartMusicBeatState) {
		if (instance is ModchartEditorState) {
			return cast(FlxG.state, ModchartEditorState)?.check_downscroll?.checked ?? utilities.Options.getData("downscroll");
		}
		// need to test each engine
		// not expecting all to work
		#if PSYCH
		#if (PSYCHVERSION >= "0.7")
		return ClientPrefs.downScroll;
		#else
		return ClientPrefs.data.downScroll;
		#end
		#elseif LEATHER
		return utilities.Options.getData("downscroll");
		#elseif ANDROMEDA // dunno why youd use this on andromeda but whatever, already got its own cool modchart system
		return instance.currentOptions.downScroll;
		#elseif KADE
		return PlayStateChangeables.useDownscroll;
		#elseif FOREVER_LEGACY // forever might not work just yet because of the multiple strumgroups
		return Init.trueSettings.get('Downscroll');
		#elseif FPSPLUS
		return Config.downscroll;
		#elseif MIC_D_UP // basically no one uses this anymore
		return MainVariables._variables.scroll == "down"
		#else
		return false;
		#end
	}

	public static inline function getMiddlescroll(instance:ModchartMusicBeatState) {
		#if PSYCH
		#if (PSYCHVERSION >= "0.7")
		return ClientPrefs.middleScroll;
		#else
		return ClientPrefs.data.middleScroll;
		#end
		#elseif LEATHER
		return utilities.Options.getData("middlescroll");
		#else
		return false;
		#end
	}

	public static inline function getScrollSpeed(instance:PlayState) {
		if (instance == null)
			return PlayState.SONG.speed;

		#if (PSYCH || ANDROMEDA)
		return instance.songSpeed;
		#elseif LEATHER @:privateAccess
		return instance.speed;
		#elseif KADE
		return PlayStateChangeables.scrollSpeed == 1 ? PlayState.SONG.speed : PlayStateChangeables.scrollSpeed;
		#else
		return PlayState.SONG.speed; // most engines just use this
		#end
	}

	public static function getNoteOffsetX(daNote:Note, instance:ModchartMusicBeatState):Float {
		#if PSYCH
		return daNote.offsetX;
		#elseif LEATHER
		var lane = daNote.noteData;
		if (daNote.mustPress)
			lane += NoteMovement.keyCount;
		var strum = instance.playfieldRenderer.strumGroup.members[lane];
		if (strum == null)
			return 0;
		// Centers the note on its strum. Computed live instead of cached so that
		// it stays correct when a skin or a scale modifier changes the widths.
		return (strum.width - daNote.width) / 2;
		#else
		return (daNote.isSustainNote ? 37 : 0); // the magic number
		#end
	}

	static var currentFakeCrochet:Float = -1;
	static var lastBpm:Float = -1;

	public static function getFakeCrochet() {
		if (PlayState.SONG.bpm != lastBpm) {
			currentFakeCrochet = (60 / PlayState.SONG.bpm) * 1000; // only need to calculate once
			lastBpm = PlayState.SONG.bpm;
		}
		return currentFakeCrochet;
	}

	public static function getFakeCrochetAt(time:Float):Float {
		#if LEATHER
		var bpm = Conductor.getBPMAtTime(time);
		if (bpm > 0) return (60 / bpm) * 1000;
		#end
		var bpm = PlayState.SONG != null ? PlayState.SONG.bpm : Conductor.bpm;
		var map = Conductor.bpmChangeMap;
		if (map != null)
			for (change in map)
				if (change.songTime <= time) bpm = change.bpm; else break;
		return (60 / bpm) * 1000;
	}

	public static inline function applyCameraZoomToSprite(sprite:flixel.FlxSprite, camera:flixel.FlxCamera, cameraZoom:Float):Void {
		if (camera != null && camera.zoom != 1.0) {
			var zoom = camera.zoom;
			var zoomEffect = 1.0 - cameraZoom;
			if (zoomEffect > 0) {
				var targetZoom = 1.0 + ((1.0 / zoom) - 1.0) * zoomEffect;
				sprite.x = (sprite.x - flixel.FlxG.width * 0.5) * targetZoom + flixel.FlxG.width * 0.5;
				sprite.y = (sprite.y - flixel.FlxG.height * 0.5) * targetZoom + flixel.FlxG.height * 0.5;
				sprite.scale.x *= targetZoom;
				sprite.scale.y *= targetZoom;
			}
		}
	}

	public static inline function applyCameraZoomToMesh(mesh:flixel.FlxStrip, camera:flixel.FlxCamera, cameraZoom:Float):Void {
		if (camera != null && camera.zoom != 1.0 && mesh != null && mesh.vertices != null) {
			var zoom = camera.zoom;
			var zoomEffect = 1.0 - cameraZoom;
			if (zoomEffect > 0) {
				var targetZoom = 1.0 + ((1.0 / zoom) - 1.0) * zoomEffect;
				var midX:Float = flixel.FlxG.width * 0.5;
				var midY:Float = flixel.FlxG.height * 0.5;
				var len:Int = mesh.vertices.length;
				for (i in 0...len) {
					if (i % 2 == 0) {
						mesh.vertices[i] = (mesh.vertices[i] - midX) * targetZoom + midX;
					} else {
						mesh.vertices[i] = (mesh.vertices[i] - midY) * targetZoom + midY;
					}
				}
			}
		}
	}

	public static var zNear:Float = 0;
	public static var zFar:Float = 100;
	public static var defaultFOV:Float = 90;

	static var _cachedVec3D:Vector3D = new Vector3D();
	static var _cachedPerspVec3D:Vector3D = new Vector3D();

	static var _perspCacheFOV:Float = -1;
	static var _perspCacheZNear:Float = 0;
	static var _perspCacheZFar:Float = 0;
	static var _perspTanHalfFOV:Float = 0;
	static var _perspZRange:Float = 0;

	/**
		Converts a Vector3D to its in world coordinates using perspective math
	**/
	public static function calculatePerspective(pos:Vector3D, FOV:Float, offsetX:Float = 0, offsetY:Float = 0) {
		/* math from opengl lol
			found from this website https://ogldev.org/www/tutorial12/tutorial12.html
		 */

		// TODO: maybe try using actual matrix???

		if (_perspCacheFOV != FOV || _perspCacheZNear != zNear || _perspCacheZFar != zFar) {
			_perspCacheFOV = FOV;
			_perspCacheZNear = zNear;
			_perspCacheZFar = zFar;
			_perspTanHalfFOV = Math.sin(FOV * 0.5) / Math.cos(FOV * 0.5); // faster tan
			_perspZRange = zNear - zFar;
		}

		var newz = pos.z - 1;
		var zRange = _perspZRange;
		var tanHalfFOV = _perspTanHalfFOV;
		if (pos.z > 1) // if above 1000 z basically
			newz = 0; // should stop weird mirroring with high z values

		// var m00 = 1/(tanHalfFOV);
		// var m11 = 1/tanHalfFOV;
		// var m22 = (-zNear - zFar) / zRange; //isnt this just 1 lol
		// var m23 = 2 * zFar * zNear / zRange;
		// var m32 = 1;

		var xOffsetToCenter = pos.x - (FlxG.width * 0.5); // so the perspective focuses on the center of the screen
		var yOffsetToCenter = pos.y - (FlxG.height * 0.5);

		var zPerspectiveOffset = (newz + (2 * zFar * zNear / zRange));

		// xOffsetToCenter += (offsetX / (1/-zPerspectiveOffset));
		// yOffsetToCenter += (offsetY / (1/-zPerspectiveOffset));
		xOffsetToCenter += (offsetX * -zPerspectiveOffset);
		yOffsetToCenter += (offsetY * -zPerspectiveOffset);

		var xPerspective = xOffsetToCenter * (1 / tanHalfFOV);
		var yPerspective = yOffsetToCenter * tanHalfFOV;
		xPerspective /= -zPerspectiveOffset;
		yPerspective /= -zPerspectiveOffset;

		pos.x = xPerspective + (FlxG.width * 0.5); // offset it back to normal
		pos.y = yPerspective + (FlxG.height * 0.5);
		pos.z = zPerspectiveOffset;

		// pos.z -= 1;
		// pos = perspectiveMatrix.transformVector(pos);

		return pos;
	}

	/**
		Returns in-world 3D coordinates using polar angle, azimuthal angle and a radius.
		(Spherical to Cartesian)

		@param	theta Angle used along the polar axis.
		@param	phi Angle used along the azimuthal axis.
		@param	radius Distance to center.
	**/
	public static function getCartesianCoords3D(theta:Float, phi:Float, radius:Float):Vector3D {
		var pos = _cachedVec3D;
		if (phi == 0) {
			pos.x = 0;
			pos.y = radius;
			pos.z = 0;
			return pos;
		}
		var rad = FlxAngle.TO_RAD;
		var sinPhi = Math.sin(phi * rad);
		pos.x = Math.cos(theta * rad) * sinPhi * radius;
		pos.y = Math.cos(phi * rad) * radius;
		pos.z = Math.sin(theta * rad) * sinPhi * radius;

		return pos;
	}

	public static function getFlxEaseByString(?ease:String = '') {
		if (ease == null) ease = '';
		var cleanEase = ease.split(',')[0].toLowerCase().trim();
		switch (cleanEase) {
			case 'backin':
				return FlxEase.backIn;
			case 'backinout':
				return FlxEase.backInOut;
			case 'backout':
				return FlxEase.backOut;
			case 'bouncein':
				return FlxEase.bounceIn;
			case 'bounceinout':
				return FlxEase.bounceInOut;
			case 'bounceout':
				return FlxEase.bounceOut;
			case 'circin':
				return FlxEase.circIn;
			case 'circinout':
				return FlxEase.circInOut;
			case 'circout':
				return FlxEase.circOut;
			case 'cubein':
				return FlxEase.cubeIn;
			case 'cubeinout':
				return FlxEase.cubeInOut;
			case 'cubeout':
				return FlxEase.cubeOut;
			case 'elasticin':
				return FlxEase.elasticIn;
			case 'elasticinout':
				return FlxEase.elasticInOut;
			case 'elasticout':
				return FlxEase.elasticOut;
			case 'expoin':
				return FlxEase.expoIn;
			case 'expoinout':
				return FlxEase.expoInOut;
			case 'expoout':
				return FlxEase.expoOut;
			case 'quadin':
				return FlxEase.quadIn;
			case 'quadinout':
				return FlxEase.quadInOut;
			case 'quadout':
				return FlxEase.quadOut;
			case 'quartin':
				return FlxEase.quartIn;
			case 'quartinout':
				return FlxEase.quartInOut;
			case 'quartout':
				return FlxEase.quartOut;
			case 'quintin':
				return FlxEase.quintIn;
			case 'quintinout':
				return FlxEase.quintInOut;
			case 'quintout':
				return FlxEase.quintOut;
			case 'sinein':
				return FlxEase.sineIn;
			case 'sineinout':
				return FlxEase.sineInOut;
			case 'sineout':
				return FlxEase.sineOut;
			case 'smoothstepin':
				return FlxEase.smoothStepIn;
			case 'smoothstepinout':
				return FlxEase.smoothStepInOut;
			case 'smoothstepout':
				return FlxEase.smoothStepInOut;
			case 'smootherstepin':
				return FlxEase.smootherStepIn;
			case 'smootherstepinout':
				return FlxEase.smootherStepInOut;
			case 'smootherstepout':
				return FlxEase.smootherStepOut;
		}
		return FlxEase.linear;
	}

	public static function getTimeFromBeat(beat:Float) {
		var curBpm = PlayState.SONG != null ? PlayState.SONG.bpm : Conductor.bpm;
		if (beat < 0) {
			return beat * (60 / curBpm) * 1000;
		}

		var totalTime:Float = 0;
		var bpmMap = Conductor.bpmChangeMap;
		var bpmIndex:Int = 0;
		var maxBpm = bpmMap != null ? bpmMap.length : 0;
		for (i in 0...Math.floor(beat)) {
			while (bpmIndex < maxBpm && totalTime >= bpmMap[bpmIndex].songTime) {
				curBpm = bpmMap[bpmIndex].bpm;
				bpmIndex++;
			}
			totalTime += (60 / curBpm) * 1000;
		}

		var leftOverBeat = beat - Math.floor(beat);
		totalTime += (60 / curBpm) * 1000 * leftOverBeat;

		return totalTime;
	}
}
