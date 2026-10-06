package modcharting;

import Lambda;
import modcharting.BezierPathTween;
import modcharting.BezierPathNumTween;
import flixel.util.FlxTimer.FlxTimerManager;
import flixel.math.FlxMath;
import flixel.tweens.FlxTween;
import flixel.tweens.FlxEase;
import flixel.graphics.FlxGraphic;
import flixel.util.FlxColor;
import flixel.FlxStrip;
import flixel.graphics.tile.FlxDrawTrianglesItem.DrawData;
import openfl.geom.Vector3D;
import flixel.util.FlxSpriteUtil;
import flixel.graphics.frames.FlxFrame;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.FlxSprite;
import flixel.FlxG;
import flixel.FlxCamera;
import modcharting.Modifier;
import modcharting.LanePathRenderer;
import flixel.system.FlxAssets.FlxShader;
import modcharting.TweenManager;
#if MODCHART_FOXLITE
import modcharting.foxlite.FoxPlayfieldBridge;
// `FovModifier`, `DepthModifier` and `TiltModifier` are deliberately not imported here. They live
// in this package, are not guarded, and are reached from the `modifierTable` scan by `Std.downcast`.
#end
#if LEATHER
import states.PlayState;
import game.Note;
import game.StrumNote;
import game.Conductor;
#elseif (PSYCH && PSYCHVERSION >= "0.7")
import states.PlayState;
import objects.Note;
import objects.StrumNote;
#else
import PlayState;
import Note;
import StrumNote;
#end

using StringTools;

// a few todos im gonna leave here:
// setup quaternions for everything else (incoming angles and the rotate mod)
// do add and remove buttons on stacked events in editor
// fix switching event type in editor so you can actually do set events
// finish setting up tooltips in editor
// start documenting more stuff idk

typedef StrumNoteType = #if (PSYCH || LEATHER) StrumNote #elseif KADE StaticArrow #elseif FOREVER_LEGACY UIStaticArrow #elseif ANDROMEDA Receptor #else FlxSprite #end;

class PlayfieldRenderer extends FlxSprite // extending flxsprite just so i can edit draw
{
	public var strumGroup:FlxTypedGroup<StrumNoteType>;
	public var notes:FlxTypedGroup<Note>;
	public var instance:ModchartMusicBeatState;
	public var playStateInstance:PlayState;
	public var playfields:Array<Playfield> = []; // adding an extra playfield will add 1 for each player

	public var eventManager:ModchartEventManager;
	public var modifierTable:ModTable;
	public var tweenManager:TweenManager = null;
	public var timerManager:FlxTimerManager = null;

	public var modchart:ModchartFile;
	public var inEditor:Bool = false;
	public var editorPaused:Bool = false;

	public var speed:Float = 1.0;

	public var isDownscroll:Bool = false;
	public var isMiddlescroll:Bool = false;

	public var modifiers(get, default):Map<String, Modifier>;

	public var lanePaths:Array<LanePathRenderer> = [];
	public var showLanePaths:Bool = true;

	var _mirrored:Bool = false;

	var _vec3:Vector3D = new Vector3D();
	var _vec3b:Vector3D = new Vector3D();

	/**
	 * Hardware accelerated 3D path, or `null` when built without `MODCHART_FOXLITE`.
	 *
	 * Only notes and strums go through it. Sustain strips keep the classic mesh path, since a
	 * `FoxSpriteShader` projects a textured quad and a sustain is a variable length strip with
	 * its own vertex construction.
	 */
	#if MODCHART_FOXLITE
	public var foxBridge:FoxPlayfieldBridge;

	// Diagnostics for `applyFoxLiteModifiers()`. The scan runs every frame, so without these the
	// only thing visible on a broken setup is silence: a missing modifier, a scoping mistake and a
	// working tween all look identical from the outside.
	var foxReportedScan = false;
	var foxReportedActive = false;
	var foxLastApplied = '';
	#end

	/**
	 * Whether FoxLite owns the projection for this frame.
	 *
	 * Compiles down to a constant `false` without the define, so the classic path below stays
	 * completely untouched and no dead branches are emitted. When it is true the classic
	 * `ModchartUtil.calculatePerspective()` bake has to be skipped: the shader performs that
	 * projection, so doing it on the CPU as well would apply the perspective divide twice.
	 */
	inline function foxActive():Bool {
		#if MODCHART_FOXLITE
		return foxBridge != null && foxBridge.active && foxBridge.enabled;
		#else
		return false;
		#end
	}

	private function get_modifiers():Map<String, Modifier> {
		return modifierTable.modifiers; // back compat with lua modcharts
	}

	public function new(strumGroup:FlxTypedGroup<StrumNoteType>, notes:FlxTypedGroup<Note>, instance:ModchartMusicBeatState)
	{
		super(0, 0);

		this.strumGroup = strumGroup;
		this.notes = notes;
		this.instance = instance;

		if (instance is PlayState)
			playStateInstance = cast instance;

		isDownscroll = ModchartUtil.getDownscroll(instance);
		isMiddlescroll = ModchartUtil.getMiddlescroll(instance);

		strumGroup.visible = false;
		notes.visible = false;

		instance.playfieldRenderer = this;

		tweenManager = new TweenManager();
		timerManager = new FlxTimerManager();
		eventManager = new ModchartEventManager(this);
		modifierTable = new ModTable(instance, this);

		#if MODCHART_FOXLITE
		// Wrapped so a missing or broken FoxLite install degrades to the classic renderer
		// instead of taking the whole game down. `new()` already swallows its own failures and
		// leaves `active` false, this covers anything thrown outside that.
		try {
			foxBridge = new FoxPlayfieldBridge(FlxG.width, FlxG.height, ModchartUtil.defaultFOV);
			trace('[modcharting-tools] FoxLite bridge creado. active=' + Std.string(foxBridge.active) + ' enabled=' + Std.string(foxBridge.enabled)
				+ ' fovBase=' + Std.string(ModchartUtil.defaultFOV));
		} catch (e) {
			foxBridge = null;
			trace('[modcharting-tools] FoxLite bridge could not be created, using the classic renderer: ' + Std.string(e));
		}

		// Registered here rather than in `ModTable.loadDefaultModifiers()` so the classic build
		// keeps compiling without any FoxLite types in scope.
		//
		// No instances are pre-seeded: `applyFoxLiteModifiers()` finds these three by class, so a
		// blank placeholder tagged `foxfov` would just sit in the table competing with the real one
		// the chart defines. Absent modifiers are handled by the resets in that method instead.
		#end

		addNewPlayfield(0, 0, 0);

		modchart = new ModchartFile(this);
	}

	public inline function addNewPlayfield(?x:Float = 0, ?y:Float = 0, ?z:Float = 0, ?alpha:Float = 1) {
		playfields.push(new Playfield(x, y, z, alpha));
	}

	public function setMirrored(mirrored:Bool) {
		_mirrored = mirrored;
		if (!mirrored) return;

		var screenCenterX = flixel.FlxG.width * 0.5;
		for (i in 0...NoteMovement.defaultStrumX.length) {
			var strumWidth = NoteMovement.arrowSizes[i] > 0 ? NoteMovement.arrowSizes[i] : 112;
			NoteMovement.defaultStrumX[i] = screenCenterX + (screenCenterX - NoteMovement.defaultStrumX[i] - strumWidth);
		}
	}

	override function update(elapsed:Float) {
		try {
			eventManager.update(elapsed);
			#if LEATHER
			var scaledElapsed = elapsed * (Std.isOfType(flixel.FlxG.state, states.PlayState) ? states.PlayState.songMultiplier : 1.0);
			#elseif PSYCH
			var scaledElapsed = elapsed * PlayState.instance.playbackRate;
			#else
			var scaledElapsed = elapsed;
			#end
			tweenManager.update(scaledElapsed); // should be automatically paused when you pause in game
			timerManager.update(scaledElapsed);
		} catch (e) {
			trace(e);
		}
		super.update(elapsed);
	}

	override public function draw() {
		if (alpha <= 0.001 || !visible)
			return;

		isDownscroll = ModchartUtil.getDownscroll(instance);
		isMiddlescroll = ModchartUtil.getMiddlescroll(instance);

		strumGroup.cameras = this.cameras;
		notes.cameras = this.cameras;

		var positions = getNotePositions();
		try {
			#if MODCHART_FOXLITE
			if (foxActive()) {
				if (!foxReportedActive) {
					foxReportedActive = true;
					trace('[modcharting-tools] FoxLite ACTIVO: las notas y strums se dibujan en 3D. Fov/Depth/Tilt ya tienen efecto.');
				}
				// Camera state is playfield wide, so the modifiers are pulled once here instead
				// of running through the per note pipeline. Must be before beginFrame(): that is
				// what turns the tilt and FOV the modifiers wrote into matrices.
				applyFoxLiteModifiers();
				// Must run before drawStuff(): updates the camera matrices and the playfield
				// pivot, which every note's world transform is parented to.
				foxBridge.beginFrame(0, ModchartUtil.defaultFOV, FlxG.width, FlxG.height);
			} else if (!foxReportedActive && foxBridge != null) {
				// The single most common "my camera modifiers do nothing": the chart builds, the
				// bridge exists, but something has it switched off. `foxActive()` folds three
				// conditions together, so name the one that failed.
				foxReportedActive = true;
				trace('[modcharting-tools] FoxLite INACTIVO: la camara y los modifiers Fov/Depth/Tilt NO se aplican. Razón -> '
					+ (foxBridge == null ? 'bridge no creado' : (!foxBridge.active ? 'bridge.active = false (fallo al inicializar el contexto de render)' : 'bridge.enabled = false')));
			}
			#end

			drawStuff(positions);

			#if MODCHART_FOXLITE
			if (foxActive()) {
				// Drops wrappers for notes that no longer exist at their index. Also the natural
				// place to reset the per note flags, since every note is drawn inside drawStuff().
				foxBridge.endFrame(notes.members.length, strumGroup.members.length);
				resetFoxLiteFlags();
			}
			#end
		} catch (e) {
			trace(e + '\n' + e.stack);
			#if MODCHART_FOXLITE
			resetFoxLiteFlags();
			#end
		}
		for (data in positions)
			NotePositionData.recycle(data);
	}

	public function addDataToStrum(strumData:NotePositionData, strum:StrumNoteType) {
		strum.x = strumData.x;
		strum.y = strumData.y;
		strum.angle3D.x = strumData.angleX;
		strum.angle3D.y = strumData.angleY;
		strum.angle3D.z = strumData.angleZ;
		strum.scale.x = strumData.scaleX;
		strum.scale.y = strumData.scaleY;
		strum.skew.x = strumData.skewX;
		strum.skew.y = strumData.skewY;
		strum.setColorTransform(1, 1, 1, strumData.alpha, strumData.redOffset, strumData.greenOffset, strumData.blueOffset);
	}

	public function getDataForStrum(i:Int, pf:Int) {
		var strumX = NoteMovement.defaultStrumX[i];
		var strumY = NoteMovement.defaultStrumY[i];
		var strumZ = 0;
		var strumScaleX = NoteMovement.defaultScale[i];
		var strumScaleY = NoteMovement.defaultScale[i];
		var strumSkewX = NoteMovement.defaultSkewX[i];
		var strumSkewY = NoteMovement.defaultSkewY[i];
		var strumData:NotePositionData = NotePositionData.get();
		strumData.setupStrum(strumX, strumY, strumZ, i, strumScaleX, strumScaleY, strumSkewX, strumSkewY, pf);
		playfields[pf].applyOffsets(strumData);
		modifierTable.applyStrumMods(strumData, i, pf);
		return strumData;
	}

	public function addDataToNote(noteData:NotePositionData, daNote:Note) {
		daNote.x = noteData.x;
		daNote.y = noteData.y;
		daNote.z = noteData.z;
		daNote.angle3D.x = noteData.angleX;
		daNote.angle3D.y = noteData.angleY;
		daNote.angle3D.z = noteData.angleZ;
		daNote.scale.x = noteData.scaleX;
		daNote.scale.y = noteData.scaleY;
		daNote.skew.x = noteData.skewX;
		daNote.skew.y = noteData.skewY;
		daNote.setColorTransform(1, 1, 1, noteData.alpha, noteData.redOffset, noteData.greenOffset, noteData.blueOffset);
	}

	public function createDataFromNote(noteIndex:Int, playfieldIndex:Int, curPos:Float, noteDist:Float, incomingAngle:Array<Float>) {
		var noteX = notes.members[noteIndex].x;
		var noteY = notes.members[noteIndex].y;
		var noteZ = notes.members[noteIndex].z;
		var lane = getLane(noteIndex);
		var noteScaleX = NoteMovement.defaultScale[lane];
		var noteScaleY = NoteMovement.defaultScale[lane];
		var noteSkewX = notes.members[noteIndex].skew.x;
		var noteSkewY = notes.members[noteIndex].skew.y;

		var noteAlpha:Float = #if PSYCH notes.members[noteIndex].multAlpha; #else notes.members[noteIndex].isSustainNote ? 1 : 1; #end

		var noteData:NotePositionData = NotePositionData.get();
		noteData.setupNote(noteX, noteY, noteZ, lane, noteScaleX, noteScaleY, noteSkewX, noteSkewY, playfieldIndex, noteAlpha, curPos, noteDist,
			incomingAngle[0], incomingAngle[1], notes.members[noteIndex].strumTime, noteIndex);
		playfields[playfieldIndex].applyOffsets(noteData);
		return noteData;
	}

	public function getNoteCurPos(noteIndex:Int, strumTimeOffset:Float = 0) {
		if (notes.members[noteIndex].isSustainNote && !isDownscroll)
			strumTimeOffset += Conductor.stepCrochet; // fix upscroll lol
		var distance = (Conductor.songPosition - notes.members[noteIndex].strumTime) + strumTimeOffset;
		return distance * notes.members[noteIndex].speed;
	}

	public inline function getLane(noteIndex:Int) {
		return (notes.members[noteIndex].mustPress ? notes.members[noteIndex].noteData + NoteMovement.keyCount : notes.members[noteIndex].noteData);
	}

	public function getNoteDist(noteIndex:Int) {
		var noteDist = -0.45;
		if (isDownscroll)
			noteDist *= -1;
		return noteDist;
	}

	public function getNotePositions() {
		var notePositions:Array<NotePositionData> = [];
		for (pf in 0...playfields.length) {
			for (i in 0...strumGroup.members.length) {
				var strumData = getDataForStrum(i, pf);
				notePositions.push(strumData);
			}
			for (modName => mod in modifierTable.modifiers) {
				if (mod.currentValue != mod.baseValue) {
					var extra = mod.gatherExtraStrumData(pf);
					if (extra != null) {
						for (e in extra)
							notePositions.push(e);
					}
				}
			}
			for (i in 0...notes.members.length) {
				var songSpeed = notes.members[i].speed;

				var lane = getLane(i);

				var noteDist = getNoteDist(i);
				noteDist = modifierTable.applyNoteDistMods(noteDist, lane, pf);

				var sustainTimeThingy:Float = 0;

				var curPos = getNoteCurPos(i, sustainTimeThingy);
				curPos = modifierTable.applyCurPosMods(lane, curPos, pf);

				if ((notes.members[i].wasGoodHit || (notes.members[i].prevNote != null && notes.members[i].prevNote.wasGoodHit))
					&& curPos >= 0
					&& notes.members[i].isSustainNote)
					curPos = 0; // sustain clip

				var incomingAngle:Array<Float> = modifierTable.applyIncomingAngleMods(lane, curPos, pf);
				if (noteDist < 0)
					incomingAngle[0] += 180; // make it match for both scrolls

				// get the general note path
				NoteMovement.setNotePath(notes.members[i], lane, songSpeed, curPos, noteDist, incomingAngle[0], incomingAngle[1]);

				// save the position data
				var noteData = createDataFromNote(i, pf, curPos, noteDist, incomingAngle);

				// add offsets to data with modifiers
				modifierTable.applyNoteMods(noteData, lane, curPos, pf);

				// add position data to list
				notePositions.push(noteData);
			}
			for (modName => mod in modifierTable.modifiers) {
				if (mod.currentValue != mod.baseValue) {
					var extra = mod.gatherExtraNoteData(pf);
					if (extra != null) {
						for (e in extra)
							notePositions.push(e);
					}
				}
			}
		}
		// sort by z before drawing
		notePositions.sort(function(a, b) {
			if (a.z < b.z)
				return -1;
			else if (a.z > b.z)
				return 1;
			else {
				// Draw sustain body notes before sustain end notes so holdend renders ON TOP of hold body
				var noteA = notes.members[a.index];
				var noteB = notes.members[b.index];
				if (noteA != null && noteB != null) {
					if (!noteA.isSustainNote && noteB.isSustainNote) return -1;
					if (noteA.isSustainNote && !noteB.isSustainNote) return 1;
					if (noteA.isSustainNote && noteB.isSustainNote) {
						var animA = (noteA.animation.curAnim != null) ? noteA.animation.curAnim.name : "";
						var animB = (noteB.animation.curAnim != null) ? noteB.animation.curAnim.name : "";
						var isEndA = animA.endsWith("end");
						var isEndB = animB.endsWith("end");
						if (!isEndA && isEndB) return -1;
						if (isEndA && !isEndB) return 1;
					}
				}
				return 0;
			}
		});
		return notePositions;
	}

	public function drawStrum(noteData:NotePositionData) {
		if (noteData.alpha <= 0)
			return;
		// When FoxLite is active the shader does the projection, so `changeX` has to stay false
		// to keep the classic `calculatePerspective()` bake below from dividing twice.
		var fox:Bool = foxActive();
		var changeX:Bool = !fox && noteData.z != 0;
		var strumNote = strumGroup.members[noteData.index];
		var thisNotePos:Vector3D;
		if (changeX) {
			_vec3b.setTo(noteData.x + (strumNote.width / 2), noteData.y + (strumNote.height / 2), noteData.z * 0.001);
			thisNotePos = ModchartUtil.calculatePerspective(_vec3b,
				ModchartUtil.defaultFOV * (Math.PI / 180),
				-(strumNote.width / 2),
				-(strumNote.height / 2));
		} else {
			_vec3.setTo(noteData.x, noteData.y, 0);
			thisNotePos = _vec3;
		}

		noteData.x = thisNotePos.x;
		noteData.y = thisNotePos.y;
		if (changeX) {
			noteData.scaleX *= (1 / -thisNotePos.z);
			noteData.scaleY *= (1 / -thisNotePos.z);
		}

		addDataToStrum(noteData, strumNote);
		strumNote.scrollFactor.set(noteData.cameraScrollX, noteData.cameraScrollY);
		strumNote.cameras = (noteData.camera != null) ? [noteData.camera] : this.cameras;

		var oldX = strumNote.x;
		var oldY = strumNote.y;
		var oldScaleX = strumNote.scale.x;
		var oldScaleY = strumNote.scale.y;

		if (noteData.camera != null && noteData.camera.zoom != 1.0) {
			var zoom = noteData.camera.zoom;
			var zoomEffect = 1.0 - noteData.cameraZoom;
			if (zoomEffect > 0) {
				var targetZoom = 1.0 + ((1.0 / zoom) - 1.0) * zoomEffect;
				strumNote.x = (strumNote.x - flixel.FlxG.width / 2) * targetZoom + flixel.FlxG.width / 2;
				strumNote.y = (strumNote.y - flixel.FlxG.height / 2) * targetZoom + flixel.FlxG.height / 2;
				strumNote.scale.x *= targetZoom;
				strumNote.scale.y *= targetZoom;
			}
		}

		#if MODCHART_FOXLITE
		if (fox) {
			// FlxFox3DSprite.draw() reads sprite.camera, so this has to be pinned before the
			// uniforms are baked rather than relying on the `cameras` assignment above.
			var foxCam:FlxCamera = (noteData.camera != null) ? noteData.camera : this.camera;
			foxBridge.applyStrum(strumNote, noteData.index, noteData.z, noteData.angleX, noteData.angleY, noteData.angleZ, foxCam);
			markFoxLite(strumNote, true);
		}
		#end

		strumNote.draw();

		#if MODCHART_FOXLITE
		markFoxLite(strumNote, false, true, noteData.index);
		#end

		strumNote.x = oldX;
		strumNote.y = oldY;
		strumNote.scale.x = oldScaleX;
		strumNote.scale.y = oldScaleY;
	}

	public function drawNote(noteData:NotePositionData) {
		if (noteData.alpha <= 0.001 || !visible || alpha <= 0.001)
			return;
	
		var fox:Bool = foxActive();
		var changeX:Bool = !fox && noteData.z != 0;
		var daNote = notes.members[noteData.index];
		var thisNotePos:Vector3D;
		if (changeX) {
			_vec3b.setTo(noteData.x + (daNote.width / 2) + ModchartUtil.getNoteOffsetX(daNote, instance),
				noteData.y + (daNote.height / 2), noteData.z * 0.001);
			thisNotePos = ModchartUtil.calculatePerspective(_vec3b,
				ModchartUtil.defaultFOV * (Math.PI / 180),
				-(daNote.width / 2),
				-(daNote.height / 2));
		} else {
			_vec3.setTo(noteData.x, noteData.y, 0);
			thisNotePos = _vec3;
		}
		
		if(daNote.isSustainNote){
			if(!changeX && !fox){
				thisNotePos.x += daNote.width;
			}
			var animName = (daNote.animation.curAnim != null) ? daNote.animation.curAnim.name : "";
			if(!animName.endsWith("end")){
				noteData.scaleY *= Conductor.stepCrochet / 100 * Note.SCALE_MULT * daNote.speed;
			}
		}

		noteData.x = thisNotePos.x;
		noteData.y = thisNotePos.y;
		if (changeX) {
			noteData.scaleX *= (1 / -thisNotePos.z);
			noteData.scaleY *= (1 / -thisNotePos.z);
		}
		addDataToNote(noteData, daNote);
		daNote.scrollFactor.set(noteData.cameraScrollX, noteData.cameraScrollY);
		daNote.cameras = (noteData.camera != null) ? [noteData.camera] : this.cameras;

		var oldX = daNote.x;
		var oldY = daNote.y;
		var oldScaleX = daNote.scale.x;
		var oldScaleY = daNote.scale.y;

		if (noteData.camera != null && noteData.camera.zoom != 1.0) {
			var zoom = noteData.camera.zoom;
			var zoomEffect = 1.0 - noteData.cameraZoom;
			if (zoomEffect > 0) {
				var targetZoom = 1.0 + ((1.0 / zoom) - 1.0) * zoomEffect;
				daNote.x = (daNote.x - flixel.FlxG.width / 2) * targetZoom + flixel.FlxG.width / 2;
				daNote.y = (daNote.y - flixel.FlxG.height / 2) * targetZoom + flixel.FlxG.height / 2;
				daNote.scale.x *= targetZoom;
				daNote.scale.y *= targetZoom;
			}
		}

		#if MODCHART_FOXLITE
		if (fox && !daNote.isSustainNote) {
			var foxCam:FlxCamera = (noteData.camera != null) ? noteData.camera : this.camera;
			foxBridge.applyNote(daNote, noteData.index, noteData.z, noteData.angleX, noteData.angleY, noteData.angleZ, foxCam);
			markFoxLite(daNote, true);
		}
		#end

		daNote.draw();

		#if MODCHART_FOXLITE
		markFoxLite(daNote, false, false, noteData.index);
		#end

		daNote.x = oldX;
		daNote.y = oldY;
		daNote.scale.x = oldScaleX;
		daNote.scale.y = oldScaleY;
	}

	#if MODCHART_FOXLITE
	/**
	 * Tells a note that FoxLite owns its projection for this draw.
	 *
	 * `FlxSprite3D` needs it to skip the classic 2D rotation matrix and to refuse the
	 * `drawSimple()` blit path, which would bypass the shader entirely.
	 */
	inline function markFoxLite(sprite:FlxSprite, value:Bool, ?isStrum:Bool = false, ?index:Int = -1) {
		var sprite3D = Std.downcast(sprite, FlxSprite3D);
		if (sprite3D != null)
			sprite3D.foxLiteActive = value;
		if (!value && foxBridge != null && index >= 0) {
			if (isStrum)
				foxBridge.detachStrum(sprite, index);
			else
				foxBridge.detachNote(sprite, index);
		}
	}

	/**
	 * Clears the flag on every note and strum.
	 *
	 * The flag is normally reset right after each `draw()`, but `draw()` can throw partway
	 * through the loop and leave notes that were never reached still flagged. Since a stale
	 * `true` would permanently suppress the classic rotation for that note, this sweeps the
	 * pools. `foxLiteActive` only exists on `FlxSprite3D`, so the downcast filters out engine
	 * note types that do not extend it.
	 */
	function resetFoxLiteFlags() {
		for (strum in strumGroup.members)
			markFoxLite(strum, false);
		for (note in notes.members)
			markFoxLite(note, false);
	}

	/**
	 * Pushes the FoxLite modifiers onto the bridge.
	 *
	 * These are the only modifiers that read and write bridge state instead of per note data, so
	 * they are resolved here rather than through the note pipeline. Every modifier is called every
	 * frame, including while it is off, because that is what lets a modifier snap the bridge back
	 * to its defaults when it is stepped down.
	 *
	 * Resolved per frame rather than cached at construction so that `ModTable.add()` replacing one
	 * of them mid song is picked up, the same as for any other modifier.
	 */
	/** `'fov=0', 'scale=0.001', ...`, for the camera modifier traces. */
	function dumpSubValues(mod:Modifier):String {
		var out = '';
		for (name => sv in mod.subValues) {
			if (out.length > 0)
				out += ', ';
			out += name + '=' + Std.string(sv.value);
		}
		return '[' + out + ']';
	}

	function applyFoxLiteModifiers() {
		var totalFovOffset:Float = 0;
		var totalZScale:Float = DepthModifier.BASE_SCALE;
		var totalZOffset:Float = DepthModifier.BASE_OFFSET;
		var totalTiltX:Float = 0;
		var totalTiltY:Float = 0;
		var totalTiltZ:Float = 0;
		var totalCamX:Float = 0;
		var totalCamY:Float = 0;
		var totalCamZ:Float = 0;
		var totalPivotX:Float = 0;
		var totalPivotY:Float = 0;
		var totalPivotZ:Float = 0;

		var hasCustomZScale:Bool = false;
		var activeFovCount:Int = 0;
		var activeTiltCount:Int = 0;
		var activeDepthCount:Int = 0;

		for (mod in modifierTable.modifiers) {
			var fovMod = Std.downcast(mod, FovModifier);
			if (fovMod != null && fovMod.isActive()) {
				totalFovOffset += fovMod.getFovOffset();
				activeFovCount++;
			}

			var depthMod = Std.downcast(mod, DepthModifier);
			if (depthMod != null && depthMod.isActive()) {
				var scale = depthMod.getZScale();
				if (!hasCustomZScale) {
					totalZScale = scale;
					hasCustomZScale = true;
				} else {
					totalZScale *= (scale / DepthModifier.BASE_SCALE);
				}
				totalZOffset += depthMod.getZOffset();
				activeDepthCount++;
			}

			var tiltMod = Std.downcast(mod, TiltModifier);
			if (tiltMod != null && tiltMod.isActive()) {
				totalTiltX += tiltMod.getTiltX();
				totalTiltY += tiltMod.getTiltY();
				totalTiltZ += tiltMod.getTiltZ();
				activeTiltCount++;
			}

			var camPosMod = Std.downcast(mod, CamPosModifier);
			if (camPosMod != null && camPosMod.isActive()) {
				totalCamX += camPosMod.getCamX();
				totalCamY += camPosMod.getCamY();
				totalCamZ += camPosMod.getCamZ();
			}

			var pivotPosMod = Std.downcast(mod, PivotPosModifier);
			if (pivotPosMod != null && pivotPosMod.isActive()) {
				totalPivotX += pivotPosMod.getPivotX();
				totalPivotY += pivotPosMod.getPivotY();
				totalPivotZ += pivotPosMod.getPivotZ();
			}
		}

		if (!foxReportedScan) {
			foxReportedScan = true;
			trace('[modcharting-tools] FoxLite escaneo de modifiers de camara activos: FovCount=' + activeFovCount + ' DepthCount=' + activeDepthCount + ' TiltCount='
				+ activeTiltCount + ' (total en tabla: ' + Lambda.count(modifierTable.modifiers) + ')');
		}

		foxBridge.fovOffset = totalFovOffset;
		foxBridge.zScale = totalZScale;
		foxBridge.zOffset = totalZOffset;
		foxBridge.camera.position.setTo(totalCamX, totalCamY, foxBridge.camera.position.z + totalCamZ);
		foxBridge.pivot.position.setTo(totalPivotX, totalPivotY, totalPivotZ);
		foxBridge.setTilt(totalTiltX, totalTiltY, totalTiltZ);

		var applied = 'fovOffset=' + Std.string(foxBridge.fovOffset) + ' zScale=' + Std.string(foxBridge.zScale) + ' zOffset=' + Std.string(foxBridge.zOffset) + ' tilt=('
			+ Std.string(totalTiltX) + ', ' + Std.string(totalTiltY) + ', ' + Std.string(totalTiltZ) + ')';
		if (applied != foxLastApplied) {
			foxLastApplied = applied;
			trace('[modcharting-tools] *** FoxLite CAMARA ACTUALIZADA *** -> ' + applied);
		}
	}
	#end

	function drawSustainAsSprite(noteData:NotePositionData) {
		var daNote = notes.members[noteData.index];

		var changeX:Bool = noteData.z != 0;
		var thisNotePos:Vector3D;
		if (changeX) {
			_vec3b.setTo(noteData.x + (daNote.width / 2) + ModchartUtil.getNoteOffsetX(daNote, instance),
				noteData.y + (daNote.height / 2), noteData.z * 0.001);
			thisNotePos = ModchartUtil.calculatePerspective(_vec3b,
				ModchartUtil.defaultFOV * (Math.PI / 180),
				-(daNote.width / 2),
				-(daNote.height / 2));
		} else {
			_vec3.setTo(noteData.x, noteData.y, 0);
			thisNotePos = _vec3;
		}

		var animName = (daNote.animation.curAnim != null) ? daNote.animation.curAnim.name : "";
		var isHoldEnd = animName.endsWith("end");

		if (!isHoldEnd) {
			if (!changeX)
				thisNotePos.x += daNote.width;

			noteData.scaleY *= Conductor.stepCrochet / 100 * Note.SCALE_MULT * daNote.speed;
		}

		noteData.x = thisNotePos.x;
		noteData.y = thisNotePos.y;
		if (changeX) {
			noteData.scaleX *= (1 / -thisNotePos.z);
			noteData.scaleY *= (1 / -thisNotePos.z);
		}
		addDataToNote(noteData, daNote);
		daNote.scrollFactor.set(noteData.cameraScrollX, noteData.cameraScrollY);
		daNote.cameras = (noteData.camera != null) ? [noteData.camera] : this.cameras;

		var oldX = daNote.x;
		var oldY = daNote.y;
		var oldScaleX = daNote.scale.x;
		var oldScaleY = daNote.scale.y;

		if (noteData.camera != null && noteData.camera.zoom != 1.0) {
			var zoom = noteData.camera.zoom;
			var zoomEffect = 1.0 - noteData.cameraZoom;
			if (zoomEffect > 0) {
				var targetZoom = 1.0 + ((1.0 / zoom) - 1.0) * zoomEffect;
				daNote.x = (daNote.x - flixel.FlxG.width / 2) * targetZoom + flixel.FlxG.width / 2;
				daNote.y = (daNote.y - flixel.FlxG.height / 2) * targetZoom + flixel.FlxG.height / 2;
				daNote.scale.x *= targetZoom;
				daNote.scale.y *= targetZoom;
			}
		}

		daNote.draw();

		daNote.x = oldX;
		daNote.y = oldY;
		daNote.scale.x = oldScaleX;
		daNote.scale.y = oldScaleY;
	}

	public function drawSustainNote(noteData:NotePositionData) {
		if (noteData.alpha <= 0.001 || !visible || alpha <= 0.001)
			return;
		if(utilities.Options.getData("optimizedModcharts")){
			drawSustainAsSprite(noteData);
			return;
		}
		var daNote = notes.members[noteData.index];
		if (daNote.mesh == null)
			daNote.mesh = new SustainStrip(daNote);

		daNote.scrollFactor.set(0, 0);
		daNote.mesh.scrollFactor.x = daNote.scrollFactor.x;
		daNote.mesh.scrollFactor.y = daNote.scrollFactor.y;
		daNote.alpha = noteData.alpha;
		daNote.mesh.setColorTransform(1, 1, 1, daNote.alpha, noteData.redOffset, noteData.greenOffset, noteData.blueOffset);

		var songSpeed = daNote.speed;
		var lane = noteData.lane;

		var yOffsetThingy = (NoteMovement.arrowSizes[lane] / 2);

		_vec3.setTo(noteData.x + (daNote.width / 2) + ModchartUtil.getNoteOffsetX(daNote, instance),
			noteData.y + ((NoteMovement.arrowSizes[noteData.lane] / 2)), noteData.z * 0.001);
		var thisNotePos = ModchartUtil.calculatePerspective(_vec3,
			ModchartUtil.defaultFOV * (Math.PI / 180),
			-(daNote.width / 2), yOffsetThingy
			- (NoteMovement.arrowSizes[noteData.lane] / 2));

		var timeToNextSustain = ModchartUtil.getFakeCrochet() / 4;
		if (noteData.noteDist < 0)
			timeToNextSustain *= -1;

		var nextHalfNotePos:NotePositionData;
		var nextNotePos:NotePositionData;
		#if (PSYCH && !(PSYCHVERSION >= "0.7"))
		nextHalfNotePos = getSustainPoint(noteData, timeToNextSustain * 0.5);
		nextNotePos = getSustainPoint(noteData, timeToNextSustain);
		#else
		nextHalfNotePos = isDownscroll ? getSustainPoint(noteData,
			timeToNextSustain * 0.458) : getSustainPoint(noteData, timeToNextSustain * 0.548);
		nextNotePos = isDownscroll ? getSustainPoint(noteData,
			timeToNextSustain + 2.2) : getSustainPoint(noteData, timeToNextSustain - 2.2);
		#end

		var flipGraphic = false;

		// mod/bound to 360, add 360 for negative angles, mod again just in case
		var fixedAngY = ((noteData.incomingAngleY % 360) + 360) % 360;

		var reverseClip = (fixedAngY > 90 && fixedAngY < 270);

		if (noteData.noteDist > 0) // downscroll
		{
			if (!isDownscroll) // fix reverse
				flipGraphic = true;
		} else {
			if (isDownscroll)
				flipGraphic = true;
		}
		// render that shit
		try {
			daNote.mesh.constructVertices(noteData, thisNotePos, nextHalfNotePos, nextNotePos, flipGraphic, reverseClip);
			daNote.mesh.scrollFactor.set(noteData.cameraScrollX, noteData.cameraScrollY);
			daNote.mesh.cameras = (noteData.camera != null) ? [noteData.camera] : this.cameras;

			if (noteData.camera != null && noteData.camera.zoom != 1.0) {
				var zoom = noteData.camera.zoom;
				var zoomEffect = 1.0 - noteData.cameraZoom;
				if (zoomEffect > 0) {
					var targetZoom = 1.0 + ((1.0 / zoom) - 1.0) * zoomEffect;
					var verts = daNote.mesh.vertices;
						var halfW = flixel.FlxG.width * 0.5;
						var halfH = flixel.FlxG.height * 0.5;
						for (i in 0...verts.length) {
							if (i % 2 == 0) {
								verts[i] = (verts[i] - halfW) * targetZoom + halfW;
							} else {
								verts[i] = (verts[i] - halfH) * targetZoom + halfH;
							}
						}
				}
			}

			daNote.mesh.draw();
		} catch (e) {
			trace(e);
		}

		NotePositionData.recycle(nextHalfNotePos);
		NotePositionData.recycle(nextNotePos);
	}

    public function drawStuff(notePositions:Array<NotePositionData>) {
        for (noteData in notePositions) {
            if (noteData.isStrum)
                drawStrum(noteData);
        }
        for (noteData in notePositions) {
            if (!noteData.isStrum && notes.members[noteData.index].isSustainNote)
                drawSustainNote(noteData);
        }
        for (noteData in notePositions) {
            if (!noteData.isStrum && !notes.members[noteData.index].isSustainNote)
                drawNote(noteData);
        }
    }

	public function getSustainPoint(noteData:NotePositionData, timeOffset:Float):NotePositionData {
		var daNote:Note = notes.members[noteData.index];
		var songSpeed:Float = daNote.speed;
		var lane:Int = noteData.lane;
		var pf:Int = noteData.playfieldIndex;

		var noteDist:Float = getNoteDist(noteData.index);
		var curPos:Float = getNoteCurPos(noteData.index, timeOffset);

		curPos = modifierTable.applyCurPosMods(lane, curPos, pf);

		if ((daNote.wasGoodHit || (daNote.prevNote.wasGoodHit)) && curPos >= 0)
			curPos = 0;
		noteDist = modifierTable.applyNoteDistMods(noteDist, lane, pf);
		var incomingAngle:Array<Float> = modifierTable.applyIncomingAngleMods(lane, curPos, pf);
		if (noteDist < 0)
			incomingAngle[0] += 180;
		NoteMovement.setNotePath(daNote, lane, songSpeed, curPos, noteDist, incomingAngle[0], incomingAngle[1]);
		var noteData = createDataFromNote(noteData.index, pf, curPos, noteDist, incomingAngle);
		modifierTable.applyNoteMods(noteData, lane, curPos, pf);
		var yOffsetThingy = (NoteMovement.arrowSizes[lane] / 2);
		_vec3b.setTo(noteData.x + (daNote.width / 2) + ModchartUtil.getNoteOffsetX(daNote, instance),
			noteData.y + (NoteMovement.arrowSizes[noteData.lane] / 2), noteData.z * 0.001);
		var finalNotePos = ModchartUtil.calculatePerspective(_vec3b,
			ModchartUtil.defaultFOV * (Math.PI / 180),
			-(daNote.width / 2), yOffsetThingy
			- (NoteMovement.arrowSizes[noteData.lane] / 2));

		noteData.x = finalNotePos.x;
		noteData.y = finalNotePos.y;
		noteData.z = finalNotePos.z;

		return noteData;
	}

	public function getCorrectScrollSpeed() {
		if (inEditor)
			return PlayState.SONG.speed;
		return ModchartUtil.getScrollSpeed(playStateInstance);
	}

	public function createTween(Object:Dynamic, Values:Dynamic, Duration:Float, ?Options:TweenOptions):FlxTween {
		var tween:FlxTween = tweenManager.tween(Object, Values, Duration, Options);
		tween.manager = tweenManager;
		return tween;
	}

	public function createTweenNum(FromValue:Float, ToValue:Float, Duration:Float = 1, ?Options:TweenOptions, ?TweenFunction:Float->Void):FlxTween {
		var tween:FlxTween = tweenManager.num(FromValue, ToValue, Duration, Options, TweenFunction);
		tween.manager = tweenManager;
		return tween;
	}

	public function createBezierPathTween(Object:Dynamic, Values:Dynamic, Duration:Float, ?Options:TweenOptions):FlxTween {
		var tween:FlxTween = tweenManager.bezierPathTween(Object, Values, Duration, Options);
		tween.manager = tweenManager;
		return tween;
	}

	public function createBezierPathNumTween(Points:Array<Float>, Duration:Float, ?Options:TweenOptions, ?TweenFunction:Float->Void):FlxTween {
		var tween:FlxTween = tweenManager.bezierPathNumTween(Points, Duration, Options, TweenFunction);
		tween.manager = tweenManager;
		return tween;
	}

	override public function destroy() {
		#if MODCHART_FOXLITE
		if (foxBridge != null) {
			foxBridge.destroy();
			foxBridge = null;
		}
		#end
		if (tweenManager != null) {
			tweenManager.destroy();
			tweenManager = null;
		}
		if (timerManager != null) {
			timerManager.destroy();
			timerManager = null;
		}
		if (eventManager != null) {
			eventManager.clearEvents();
			eventManager = null;
		}
		if (modchart != null) {
			#if hscript
			if (modchart.customModifiers != null) {
				for (customMod in modchart.customModifiers) {
					if (customMod != null) customMod.destroy();
				}
			}
			#end
			modchart = null;
		}
		super.destroy();
	}
}
