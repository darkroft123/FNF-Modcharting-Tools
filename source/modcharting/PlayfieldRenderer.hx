package modcharting;

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
import modcharting.Modifier;
import modcharting.LanePathRenderer;
import flixel.system.FlxAssets.FlxShader;
import modcharting.TweenManager;
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

	var _notePositions:Array<NotePositionData> = [];
	var _vec3:Vector3D = new Vector3D();
	var _vec3b:Vector3D = new Vector3D();

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
			drawStuff(positions);
		} catch (e) {
			trace(e + '\n' + e.stack);
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
		strum.setColorTransform(strumData.redMultiplier, strumData.greenMultiplier, strumData.blueMultiplier, strumData.alpha, strumData.redOffset, strumData.greenOffset, strumData.blueOffset);
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
		strumData.finalizeColorFill();
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
		daNote.setColorTransform(noteData.redMultiplier, noteData.greenMultiplier, noteData.blueMultiplier, noteData.alpha, noteData.redOffset, noteData.greenOffset, noteData.blueOffset);
	}

	public function createDataFromNote(noteIndex:Int, playfieldIndex:Int, curPos:Float, noteDist:Float, incomingAngle:Array<Float>, ?daNote:Note = null) {
		if (daNote == null)
			daNote = notes.members[noteIndex];
		var noteX = daNote.x;
		var noteY = daNote.y;
		var noteZ = daNote.z;
		var lane = getLane(noteIndex);
		var noteScaleX = NoteMovement.defaultScale[lane];
		var noteScaleY = NoteMovement.defaultScale[lane];
		var noteSkewX = daNote.skew.x;
		var noteSkewY = daNote.skew.y;

		var noteAlpha:Float = #if PSYCH daNote.multAlpha; #else daNote.isSustainNote ? 1 : 1; #end

		var noteData:NotePositionData = NotePositionData.get();
		noteData.setupNote(noteX, noteY, noteZ, lane, noteScaleX, noteScaleY, noteSkewX, noteSkewY, playfieldIndex, noteAlpha, curPos, noteDist,
			incomingAngle[0], incomingAngle[1], daNote.strumTime, noteIndex);
		playfields[playfieldIndex].applyOffsets(noteData);
		return noteData;
	}

	inline function getNoteSustainDuration(daNote:Note):Float {
		#if LEATHER
		if (!Math.isNaN(daNote.sustainMs) && daNote.sustainMs > 0)
			return daNote.sustainMs;
		#else
		if (Reflect.hasField(daNote, "sustainMs")) {
			var ms:Dynamic = Reflect.field(daNote, "sustainMs");
			if (ms != null && !Math.isNaN(ms) && ms > 0)
				return cast ms;
		}
		#end
		return Conductor.getStepDurationAt(daNote.strumTime);
	}

	public function getNoteCurPos(noteIndex:Int, strumTimeOffset:Float = 0) {
		var daNote = notes.members[noteIndex];
		if (daNote.isSustainNote && !isDownscroll)
			strumTimeOffset += getNoteSustainDuration(daNote);
		if (daNote.isSustainNote && isDownscroll)
			strumTimeOffset -= getNoteSustainDuration(daNote);
		var distance = (Conductor.songPosition - daNote.strumTime) + strumTimeOffset;
		return distance * daNote.speed;
	}

	public inline function getLane(noteIndex:Int) {
		return (notes.members[noteIndex].mustPress ? notes.members[noteIndex].noteData + NoteMovement.keyCount : notes.members[noteIndex].noteData);
	}

	public inline function getNoteDist(noteIndex:Int) {
		var noteDist = -0.45;
		if (isDownscroll)
			noteDist *= -1;
		return noteDist;
	}

	public function getNotePositions() {
		_notePositions.resize(0);
		var hasDepth:Bool = false;
		for (pf in 0...playfields.length) {
			for (i in 0...strumGroup.members.length) {
				var strumData = getDataForStrum(i, pf);
				if (strumData.z != 0) hasDepth = true;
				_notePositions.push(strumData);
			}
			for (mod in modifierTable.modsArray) {
				if (mod.currentValue != mod.baseValue) {
					var extra = mod.gatherExtraStrumData(pf);
					if (extra != null) {
						for (data in extra) {
							if (data.z != 0) hasDepth = true;
							_notePositions.push(data);
						}
					}
				}
			}
			for (i in 0...notes.members.length) {
				var daNote = notes.members[i];
				var songSpeed = daNote.speed;

				var lane = getLane(i);

				var noteDist = getNoteDist(i);
				noteDist = modifierTable.applyNoteDistMods(noteDist, lane, pf);

		var sustainTimeThingy:Float = 0;
		var curPos = getNoteCurPos(i, sustainTimeThingy);
				curPos = modifierTable.applyCurPosMods(lane, curPos, pf);

				if ((daNote.wasGoodHit || (daNote.prevNote != null && daNote.prevNote.wasGoodHit))
					&& curPos >= 0
					&& daNote.isSustainNote)
					curPos = 0; // sustain clip

				var incomingAngle:Array<Float> = modifierTable.applyIncomingAngleMods(lane, curPos, pf);
				if (noteDist < 0)
					incomingAngle[0] += 180; // make it match for both scrolls

				// get the general note path
				NoteMovement.setNotePath(daNote, lane, songSpeed, curPos, noteDist, incomingAngle[0], incomingAngle[1]);

				// save the position data
				var noteData = createDataFromNote(i, pf, curPos, noteDist, incomingAngle, daNote);

				// add offsets to data with modifiers
				modifierTable.applyNoteMods(noteData, lane, curPos, pf);
				noteData.finalizeColorFill();

				// add position data to list
				if (noteData.z != 0) hasDepth = true;
				_notePositions.push(noteData);
			}
			for (mod in modifierTable.modsArray) {
				if (mod.currentValue != mod.baseValue) {
					var extra = mod.gatherExtraNoteData(pf);
					if (extra != null) {
						for (data in extra) {
							if (data.z != 0) hasDepth = true;
							_notePositions.push(data);
						}
					}
				}
			}
		}
		// sort by z before drawing
		if (hasDepth) {
			_notePositions.sort(function(a, b) {
				if (a.z < b.z)
					return -1;
				else if (a.z > b.z)
					return 1;
				else
					return 0;
			});
		}
		return _notePositions;
	}

	public function drawStrum(noteData:NotePositionData) {
		if (noteData.alpha <= 0)
			return;
		var changeX:Bool = noteData.z != 0;
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
			var zoomEffect = 1.0 - noteData.cameraZoom; // 0 = full comp, 1 = no comp
			if (zoomEffect > 0) {
				var targetZoom = 1.0 + ((1.0 / zoom) - 1.0) * zoomEffect;
				strumNote.x = (strumNote.x - flixel.FlxG.width / 2) * targetZoom + flixel.FlxG.width / 2;
				strumNote.y = (strumNote.y - flixel.FlxG.height / 2) * targetZoom + flixel.FlxG.height / 2;
				strumNote.scale.x *= targetZoom;
				strumNote.scale.y *= targetZoom;
			}
		}

		strumNote.draw();

		strumNote.x = oldX;
		strumNote.y = oldY;
		strumNote.scale.x = oldScaleX;
		strumNote.scale.y = oldScaleY;
	}

	public function drawNote(noteData:NotePositionData) {
		if (noteData.alpha <= 0.001 || !visible || alpha <= 0.001)
			return;
	
		var changeX:Bool = noteData.z != 0;
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
			if(!daNote.animation.curAnim.name.endsWith("end")){
				noteData.scaleY *= sustainScaleMultiplier(daNote, noteData.lane);
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

		// OpenFL ignores colorTransform when a sprite has a shader, and notes carry
		// a ColorSwap shader (their lane colors). Drop it while colorfill is active
		// so the fill color actually shows, then restore it for the next draw.
		var savedNoteShader = daNote.shader;
		if (noteData.hasColorFill) daNote.shader = null;
		daNote.draw();
		daNote.shader = savedNoteShader;

		daNote.x = oldX;
		daNote.y = oldY;
		daNote.scale.x = oldScaleX;
		daNote.scale.y = oldScaleY;
	}

	inline function sustainScaleMultiplier(daNote:Note, lane:Int):Float {
		if (daNote.inEditor)
			return getNoteSustainDuration(daNote) / 100 * Note.SCALE_MULT * daNote.speed;
		var baseScale:Float = NoteMovement.defaultScale.length > lane ? NoteMovement.defaultScale[lane] : 0.7;
		var target:Float = daNote.sustainScaleY;
		if (target <= 0)
			return 1;
		return target / baseScale;
	}

	function drawSustainAsSprite(noteData:NotePositionData) {
		var daNote = notes.members[noteData.index];

		var changeX:Bool = noteData.z != 0;

		var animName = (daNote.animation.curAnim != null) ? daNote.animation.curAnim.name : "";
		var isHoldEnd = animName.endsWith("end");

		var thisNotePos:openfl.geom.Vector3D;
		if (changeX) {
			_vec3.setTo(noteData.x + (daNote.width / 2) + ModchartUtil.getNoteOffsetX(daNote, instance),
				noteData.y + (daNote.height / 2), noteData.z * 0.001);
			thisNotePos = ModchartUtil.calculatePerspective(_vec3,
				ModchartUtil.defaultFOV * (Math.PI / 180),
				-(daNote.width / 2),
				-(daNote.height / 2));
		} else {
			_vec3.setTo(noteData.x + ModchartUtil.getNoteOffsetX(daNote, instance), noteData.y, 0);
			thisNotePos = _vec3;
		}

		if (!isHoldEnd) {
			noteData.scaleY *= sustainScaleMultiplier(daNote, noteData.lane);
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

		var tempMesh = daNote.mesh;
		var savedNoteShader = daNote.shader;
		var savedOffsetX = daNote.offset.x;
		var savedOffsetY = daNote.offset.y;
		daNote.mesh = null;
		// The renderer drives position from noteData; the engine's note offset
		// (centerOffsets on sustains) would otherwise shift the sprite off the
		// note's own position.
		daNote.offset.set(0, 0);
		if (noteData.hasColorFill) daNote.shader = null;
		daNote.draw();
		daNote.shader = savedNoteShader;
		daNote.offset.set(savedOffsetX, savedOffsetY);
		daNote.mesh = tempMesh;

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
		if (daNote == null) return;

		var meshValid:Bool = true;
		try {
			if (daNote.mesh == null)
				daNote.mesh = new SustainStrip(daNote);
			else
				daNote.mesh.updateGraphic();

			if (daNote.mesh.graphic == null || daNote.mesh.graphic.bitmap == null)
				meshValid = false;
		} catch (e:Dynamic) {
			meshValid = false;
		}

		if (!meshValid) {
			drawSustainAsSprite(noteData);
			return;
		}

		daNote.scrollFactor.set(0, 0);
		daNote.mesh.scrollFactor.x = daNote.scrollFactor.x;
		daNote.mesh.scrollFactor.y = daNote.scrollFactor.y;
		daNote.mesh.setColorTransform(noteData.redMultiplier, noteData.greenMultiplier, noteData.blueMultiplier, noteData.alpha, noteData.redOffset, noteData.greenOffset, noteData.blueOffset);

		var songSpeed = daNote.speed;
		var lane = noteData.lane;

		// makes the sustain match the center of the parent note when at weird angles
		var yOffsetThingy = (NoteMovement.arrowSizes[lane] / 2);

		_vec3.setTo(noteData.x + (daNote.width / 2) + ModchartUtil.getNoteOffsetX(daNote, instance),
			noteData.y + ((NoteMovement.arrowSizes[noteData.lane] / 2)), noteData.z * 0.001);
		var thisNotePos = ModchartUtil.calculatePerspective(_vec3,
			ModchartUtil.defaultFOV * (Math.PI / 180),
			-(daNote.width / 2), yOffsetThingy
			- (NoteMovement.arrowSizes[noteData.lane] / 2));

		var timeToNextSustain = getNoteSustainDuration(daNote);
		if (noteData.noteDist < 0) timeToNextSustain *= -1;

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

		var flipGraphic = (noteData.noteDist > 0) != isDownscroll;

		// mod/bound to 360, add 360 for negative angles, mod again just in case
		var fixedAngY = ((noteData.incomingAngleY % 360) + 360) % 360;
		var reverseClip = (fixedAngY > 90 && fixedAngY < 270);

		try {
			var savedMeshShader = daNote.mesh.shader;
			daNote.mesh.shader = (SustainStrip.showHitboxContainers || noteData.hasColorFill) ? null : daNote.shader;
			daNote.mesh.constructVertices(noteData, thisNotePos, nextHalfNotePos, nextNotePos, flipGraphic, reverseClip);
			daNote.mesh.scrollFactor.set(noteData.cameraScrollX, noteData.cameraScrollY);
			daNote.mesh.cameras = (noteData.camera != null) ? [noteData.camera] : this.cameras;

			if (noteData.camera != null && noteData.camera.zoom != 1.0) {
				var zoom = noteData.camera.zoom;
				var zoomEffect = 1.0 - noteData.cameraZoom;
				if (zoomEffect > 0) {
					var targetZoom = 1.0 + ((1.0 / zoom) - 1.0) * zoomEffect;
					for (i in 0...daNote.mesh.vertices.length) {
						if (i % 2 == 0) {
							daNote.mesh.vertices[i] = (daNote.mesh.vertices[i] - flixel.FlxG.width / 2) * targetZoom + flixel.FlxG.width / 2;
						} else {
							daNote.mesh.vertices[i] = (daNote.mesh.vertices[i] - flixel.FlxG.height / 2) * targetZoom + flixel.FlxG.height / 2;
						}
					}
				}
			}

			daNote.mesh.draw();
		} catch (e:Dynamic) {
			drawSustainAsSprite(noteData);
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
		var daNote = notes.members[noteData.index];
		var songSpeed = daNote.speed;
		var lane = noteData.lane;
		var pf = noteData.playfieldIndex;

		var noteDist = getNoteDist(noteData.index);
		var curPos = getNoteCurPos(noteData.index, timeOffset);

		curPos = modifierTable.applyCurPosMods(lane, curPos, pf);
		if ((daNote.wasGoodHit || (daNote.prevNote != null && daNote.prevNote.wasGoodHit)) && curPos >= 0)
			curPos = 0;
		noteDist = modifierTable.applyNoteDistMods(noteDist, lane, pf);
		var incomingAngle = modifierTable.applyIncomingAngleMods(lane, curPos, pf);
		if (noteDist < 0) incomingAngle[0] += 180;

		NoteMovement.setNotePath(daNote, lane, songSpeed, curPos, noteDist, incomingAngle[0], incomingAngle[1]);
		var result = createDataFromNote(noteData.index, pf, curPos, noteDist, incomingAngle, daNote);
		modifierTable.applyNoteMods(result, lane, curPos, pf);
		result.finalizeColorFill();

		var arrowSize = NoteMovement.arrowSizes[lane] / 2;
		_vec3b.setTo(result.x + (daNote.width / 2) + ModchartUtil.getNoteOffsetX(daNote, instance),
			result.y + (NoteMovement.arrowSizes[result.lane] / 2), result.z * 0.001);
		var finalPos = ModchartUtil.calculatePerspective(_vec3b,
			ModchartUtil.defaultFOV * (Math.PI / 180),
			-(daNote.width / 2), 0);
		result.x = finalPos.x;
		result.y = finalPos.y;
		result.z = finalPos.z;
		return result;
	}

	public function getCorrectScrollSpeed() {
		if (inEditor)
			return PlayState.SONG.speed; // just use this while in editor so the instance shit works
		else
			return ModchartUtil.getScrollSpeed(playStateInstance);
		return 1.0;
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
		if (modchart != null) {
			#if hscript
			for (customMod in modchart.customModifiers) {
				customMod.destroy(); // make sure the interps are dead
			}
			#end
		}
		super.destroy();
	}
}
