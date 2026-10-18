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

	public inline function addDataToStrum(strumData:NotePositionData, strum:StrumNoteType) {
		NoteRenderer.addDataToStrum(strumData, strum);
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

	public inline function addDataToNote(noteData:NotePositionData, daNote:Note) {
		NoteRenderer.addDataToNote(noteData, daNote);
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

	public inline function getNoteSustainDuration(daNote:Note):Float {
		return SustainRenderer.getNoteSustainDuration(daNote);
	}

	public function getNoteCurPos(noteIndex:Int, strumTimeOffset:Float = 0) {
		var daNote = notes.members[noteIndex];
		if (daNote.isSustainNote)
			strumTimeOffset += getNoteSustainDuration(daNote);
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

	public inline function drawStrum(noteData:NotePositionData) {
		NoteRenderer.drawStrum(this, noteData);
	}

	public inline function drawNote(noteData:NotePositionData) {
		NoteRenderer.drawNote(this, noteData);
	}

	public inline function drawSustainNote(noteData:NotePositionData) {
		SustainRenderer.drawSustainNote(this, noteData);
	}

	public inline function drawSustainAsSprite(noteData:NotePositionData) {
		SustainRenderer.drawSustainAsSprite(this, noteData);
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

	public inline function getSustainPoint(noteData:NotePositionData, timeOffset:Float):NotePositionData {
		return SustainRenderer.getSustainPoint(this, noteData, timeOffset);
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
