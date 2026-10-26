package modcharting;

import flixel.tweens.FlxEase;
import flixel.math.FlxMath;
import flixel.FlxG;
import flixel.FlxObject;
import flixel.util.FlxColor;
#if LEATHER
import states.PlayState;
import game.Note;
import game.StrumNote;
import game.Conductor;
import utilities.CoolUtil;
import modding.scripts.languages.LuaScript;
#elseif (PSYCH && PSYCHVERSION >= "0.7")
import states.PlayState;
import objects.Note;
#else
import PlayState;
import Note;
#end
import lime.math.Vector4;
import haxe.ds.List;
import flixel.group.FlxGroup.FlxTypedGroup;

using StringTools;

enum ModifierType {
	ALL;
	PLAYERONLY;
	OPPONENTONLY;
	LANESPECIFIC;
}

class TimeVector extends Vector4 {
	public var startDist:Float;
	public var endDist:Float;
	public var next:TimeVector;

	public function new(x:Float = 0, y:Float = 0, z:Float = 0, w:Float = 0) {
		super(x, y, z, w);
		startDist = 0.0;
		endDist = 0.0;
		next = null;
	}
}

class ModifierSubValue {
	public var value:Float = 0.0;
	public var baseValue:Float = 0.0;
	// Optional string sidecar: lets a subvalue carry an id/name instead of a
	// number (e.g. CameraModifier's "layer" accepts an object id like "gf").
	public var name:String = null;

	public function new(value:Float) {
		this.value = value;
		baseValue = value;
	}
}

class Modifier {
	public var baseValue:Float = 0;
	public var currentValue:Float = 0;
	public var subValues:Map<String, ModifierSubValue> = new Map<String, ModifierSubValue>();
	public var tag:String = '';
	public var type:ModifierType = ALL;
	public var playfield:Int = -1;
	public var targetLane:Int = -1;
	public var targetLanes:Array<Int> = null;
	public var instance:ModchartMusicBeatState = null;
	public var renderer:PlayfieldRenderer = null;

	public static var beat:Float = 0;

	public var notes:FlxTypedGroup<Note>;

	// reusable scratch so getIncomingAngle stops allocating a new [0,0] per call
	public var _incomingAngleScratch:Array<Float> = [0, 0];

	public function new(tag:String, ?type:ModifierType = ALL, ?playfield:Int = -1) {
		this.tag = tag;
		this.type = type;
		this.playfield = playfield;

		setupSubValues();
	}

	public function getNotePath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		if (currentValue != baseValue) {
			noteMath(noteData, lane, curPos, pf);
		}
	}

	public function getStrumPath(noteData:NotePositionData, lane:Int, pf:Int) {
		if (currentValue != baseValue) {
			strumMath(noteData, lane, pf);
		}
	}

	public function getIncomingAngle(lane:Int, curPos:Float, pf:Int):Array<Float> {
		if (currentValue != baseValue) {
			var r = incomingAngleMath(lane, curPos, pf);
			if (r != null) {
				_incomingAngleScratch[0] = r[0];
				_incomingAngleScratch[1] = r[1];
			} else {
				_incomingAngleScratch[0] = 0;
				_incomingAngleScratch[1] = 0;
			}
		} else {
			_incomingAngleScratch[0] = 0;
			_incomingAngleScratch[1] = 0;
		}
		return _incomingAngleScratch;
	}

	// cur pos is how close the note is to the strum, need to edit for boost and accel
	public function getNoteCurPos(lane:Int, curPos:Float, pf:Int) {
		if (currentValue != baseValue)
			curPos = curPosMath(lane, curPos, pf);
		return curPos;
	}

	// usually fnf does *0.45 to slow the scroll speed a little, thats what this is
	// kinda just called it notedist cuz idk what else to call it,
	// using it for reverse/scroll speed changes ig
	public function getNoteDist(noteDist:Float, lane:Int, curPos:Float, pf:Int) {
		if (currentValue != baseValue)
			noteDist = noteDistMath(noteDist, lane, curPos, pf);

		return noteDist;
	}

	public dynamic function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {} // for overriding (and for custom mods with hscript)

	public dynamic function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {}

	public dynamic function incomingAngleMath(lane:Int, curPos:Float, pf:Int):Array<Float> {
		return [0, 0];
	}

	public dynamic function curPosMath(lane:Int, curPos:Float, pf:Int) {
		return curPos;
	}

	public dynamic function noteDistMath(noteDist:Float, lane:Int, curPos:Float, pf:Int):Float {
		return noteDist;
	}

	public dynamic function setupSubValues() {}

	public dynamic function gatherExtraStrumData(pf:Int):Array<NotePositionData> { return null; }

	public dynamic function hasExtraStrumData():Bool { return false; }

	public dynamic function gatherExtraNoteData(pf:Int):Array<NotePositionData> { return null; }

	public dynamic function hasExtraNoteData():Bool { return false; }

	public dynamic function onEvent(val:Float, time:Float, ease:String, beat:Float):Void {}

	public dynamic function onSubModEvent(subMod:String, val:Float, time:Float, ease:String, beat:Float):Void {}

	public inline function checkPlayField(pf:Int):Bool // returns true if should display on current playfield
	{
		return (playfield == -1) || (pf == playfield);
	}

	public function checkLane(lane:Int):Bool // returns true if should display on current lane
	{
		switch (type) {
			case LANESPECIFIC:
				if (targetLanes != null && targetLanes.length > 0)
					return targetLanes.indexOf(lane) != -1;
				return lane == targetLane;
			case PLAYERONLY:
				return lane >= NoteMovement.keyCount;
			case OPPONENTONLY:
				return lane < NoteMovement.keyCount;
			default: // so haxe shuts the fuck up
		}
		return true;
	}

	public inline function isDownscroll():Bool {
		return instance != null && renderer != null && renderer.isDownscroll;
	}

	public inline function isMiddlescroll():Bool {
		return instance != null && renderer != null && renderer.isMiddlescroll;
	}

	public function reset() // for the editor
	{
		currentValue = baseValue;
		for (subMod in subValues)
			subMod.value = subMod.baseValue;
	}

	public function copy() {
		// for custom mods to copy from the stored ones in the map
		var mod:Modifier = new Modifier(this.tag, this.type, this.playfield);
		mod.noteMath = this.noteMath;
		mod.strumMath = this.strumMath;
		mod.incomingAngleMath = this.incomingAngleMath;
		mod.curPosMath = this.curPosMath;
		mod.noteDistMath = this.noteDistMath;
		mod.currentValue = this.currentValue;
		mod.baseValue = this.currentValue;
		mod.subValues = this.subValues;
		mod.targetLane = this.targetLane;
		mod.targetLanes = this.targetLanes;
		mod.instance = this.instance;
		mod.renderer = this.renderer;
		return mod;
	}

	public function createSubMod(name:String, startVal:Float) {
		subValues.set(name, new ModifierSubValue(startVal));
	}
}

// adding drunk and tipsy for all axis because i can

class DrunkXModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('period', new ModifierSubValue(1.0));
		subValues.set('phaseShift', new ModifierSubValue(0));
	}

	function drunkMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		return currentValue * (Math.cos(((Conductor.songPosition * 0.001)
			+ ((lane % NoteMovement.keyCount) * ((subValues.get('phaseShift').value * 0.2) + 0.2))
			+ (curPos * 0.45) * (((subValues.get('period')
				.value * 10) + 10) / FlxG.height)) * ((subValues.get('speed').value * states.PlayState.songMultiplier) * 0.2)) * Note.swagWidth * 0.5);
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += drunkMath(noteData, lane, curPos, pf);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class DrunkYModifier extends DrunkXModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.y += drunkMath(noteData, lane, curPos, pf);
	}
}

class DrunkZModifier extends DrunkXModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.z += drunkMath(noteData, lane, curPos, pf);
	}
}

// schmovin because the built in ones kinda suck lol

class SchmovinDrunkXModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('period', new ModifierSubValue(1.0));
		subValues.set('phaseShift', new ModifierSubValue(0));
	}

	function applyDrunk(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var offset = subValues.get('phaseShift').value;
		var period = subValues.get('period').value;
		var speed = (subValues.get('speed').value * states.PlayState.songMultiplier);

		var phaseShift = ((lane % NoteMovement.keyCount) * 0.5) + offset + ((curPos) * period / 3) / 222 * Math.PI;
		return Math.sin((((cast(FlxG.state, MusicBeatState).curDecStep / Conductor.timeScale[0]) + 1) * speed) / 4 * Math.PI
			+ phaseShift) * (Note.swagWidth / 2) * currentValue;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += applyDrunk(noteData, lane, curPos, pf);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class SchmovinDrunkYModifier extends SchmovinDrunkXModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.y += applyDrunk(noteData, lane, curPos, pf);
	}
}

class SchmovinDrunkZModifier extends SchmovinDrunkXModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.z += applyDrunk(noteData, lane, curPos, pf);
	}
}

class SchmovinTipsyXModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('phaseShift', new ModifierSubValue(0));
	}

	function applyTipsy(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var offset = subValues.get('phaseShift').value;
		var speed = (subValues.get('speed').value * states.PlayState.songMultiplier);

		return Math.sin(((cast(FlxG.state, states.MusicBeatState).curDecStep / Conductor.timeScale[1]) + 1) * speed / 4 * Math.PI
			+ (lane % PlayState.SONG.keyCount)
			+ offset) * (Note.swagWidth / 2) * currentValue;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += applyTipsy(noteData, lane, curPos, pf);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class SchmovinTipsyYModifier extends SchmovinTipsyXModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.y += applyTipsy(noteData, lane, curPos, pf);
	}
}

class SchmovinTipsyZModifier extends SchmovinTipsyXModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.z += applyTipsy(noteData, lane, curPos, pf);
	}
}


class TipsyXModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += currentValue * (Math.cos((Conductor.songPosition * 0.001 * (1.2) +
			(lane % NoteMovement.keyCount) * (2.0)) * (5) * subValues.get('speed')
			.value * 0.2) * Note.swagWidth * 0.4);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class TipsyYModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.y += currentValue * (Math.cos((Conductor.songPosition * 0.001 * (1.2) +
			(lane % NoteMovement.keyCount) * (2.0)) * (5) * subValues.get('speed')
			.value * 0.2) * Note.swagWidth * 0.4);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class TipsyZModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.z += currentValue * (Math.cos((Conductor.songPosition * 0.001 * (1.2) +
			(lane % NoteMovement.keyCount) * (2.0)) * (5) * subValues.get('speed')
			.value * 0.2) * Note.swagWidth * 0.4);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class ReverseModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var scrollSwitch = isDownscroll() ? -520 : 520;
		noteData.y += scrollSwitch * currentValue;
	}

	override function noteDistMath(noteDist:Float, lane:Int, curPos:Float, pf:Int) {
		return noteDist * (1 - (currentValue * 2));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class SplitModifier extends Modifier {
	override function setupSubValues() {
		baseValue = 0.0;
		currentValue = 1.0;
		subValues.set('VarA', new ModifierSubValue(0.0));
		subValues.set('VarB', new ModifierSubValue(0.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var scrollSwitch = isDownscroll() ? -520 : 520;

		var laneThing = lane % NoteMovement.keyCount;

		if (laneThing > 1)
			noteData.y += scrollSwitch * subValues.get('VarA').value;

		if (laneThing < 2)
			noteData.y += scrollSwitch * subValues.get('VarB').value;
	}

	override function noteDistMath(noteDist:Float, lane:Int, curPos:Float, pf:Int) {
		var laneThing = lane % NoteMovement.keyCount;

		if (laneThing > 1)
			return noteDist * (1 - (subValues.get('VarA').value * 2));

		if (laneThing < 2)
			return noteDist * (1 - (subValues.get('VarB').value * 2));

		return noteDist;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}

	override function reset() {
		super.reset();
		baseValue = 0.0;
		currentValue = 1.0;
	}
}

class CrossModifier extends Modifier {
	override function setupSubValues() {
		baseValue = 0.0;
		currentValue = 1.0;
		subValues.set('VarA', new ModifierSubValue(0.0));
		subValues.set('VarB', new ModifierSubValue(0.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var scrollSwitch = isDownscroll() ? -520 : 520;

		var laneThing = lane % NoteMovement.keyCount;

		if (laneThing > 0 && laneThing < 3)
			noteData.y += scrollSwitch * subValues.get('VarA').value;

		if (laneThing == 0 || laneThing == 3)
			noteData.y += scrollSwitch * subValues.get('VarB').value;
	}

	override function noteDistMath(noteDist:Float, lane:Int, curPos:Float, pf:Int) {
		var laneThing = lane % NoteMovement.keyCount;

		if (laneThing > 0 && laneThing < 3)
			return noteDist * (1 - (subValues.get('VarA').value * 2));

		if (laneThing == 0 || laneThing == 3)
			return noteDist * (1 - (subValues.get('VarB').value * 2));

		return noteDist;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}

	override function reset() {
		super.reset();
		baseValue = 0.0;
		currentValue = 1.0;
	}
}

class AlternateModifier extends Modifier {
	override function setupSubValues() {
		baseValue = 0.0;
		currentValue = 1.0;
		subValues.set('VarA', new ModifierSubValue(0.0));
		subValues.set('VarB', new ModifierSubValue(0.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var scrollSwitch = isDownscroll() ? -520 : 520;
		if (lane % 2 == 1)
			noteData.y += scrollSwitch * subValues.get('VarA').value;

		if (lane % 2 == 0)
			noteData.y += scrollSwitch * subValues.get('VarB').value;
	}

	override function noteDistMath(noteDist:Float, lane:Int, curPos:Float, pf:Int) {
		if (lane % 2 == 1)
			return noteDist * (1 - (subValues.get('VarA').value * 2));

		if (lane % 2 == 0)
			return noteDist * (1 - (subValues.get('VarB').value * 2));

		return noteDist;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}

	override function reset() {
		super.reset();
		baseValue = 0.0;
		currentValue = 1.0;
	}
}

class IncomingAngleModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('x', new ModifierSubValue(0.0));
		subValues.set('y', new ModifierSubValue(0.0));
		currentValue = 1.0;
	}

	override function incomingAngleMath(lane:Int, curPos:Float, pf:Int) {
		return [subValues.get('x').value, subValues.get('y').value];
	}

	override function reset() {
		super.reset();
		currentValue = 1.0; // the code that stop the mod from running gets confused when it resets in the editor i guess??
	}
}

class RotateModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('x', new ModifierSubValue(0.0));
		subValues.set('y', new ModifierSubValue(0.0));

		subValues.set('rotatePointX', new ModifierSubValue((FlxG.width / 2) - (NoteMovement.arrowSize / 2)));
		subValues.set('rotatePointY', new ModifierSubValue((FlxG.height / 2) - (NoteMovement.arrowSize / 2)));
		currentValue = 1.0;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var xPos = NoteMovement.defaultStrumX[lane];
		var yPos = NoteMovement.defaultStrumY[lane];
		var rotX = ModchartUtil.getCartesianCoords3D(subValues.get('x').value, 90, xPos - subValues.get('rotatePointX').value);
		noteData.x += rotX.x + subValues.get('rotatePointX').value - xPos;
		var rotXZ = rotX.z;
		var rotY = ModchartUtil.getCartesianCoords3D(90, subValues.get('y').value, yPos - subValues.get('rotatePointY').value);
		noteData.y += rotY.y + subValues.get('rotatePointY').value - yPos;
		noteData.z += rotXZ + rotY.z;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}

	override function reset() {
		super.reset();
		currentValue = 1.0;
	}
}

class StrumLineRotateModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('x', new ModifierSubValue(0.0));
		subValues.set('y', new ModifierSubValue(0.0));
		subValues.set('z', new ModifierSubValue(90.0));
		currentValue = 1.0;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var laneShit = lane % NoteMovement.keyCount;
		var offsetThing = 0.5;
		var halfKeyCount = NoteMovement.keyCount / 2;
		if (lane < halfKeyCount) {
			offsetThing = -0.5;
			laneShit = lane + 1;
		}
		var distFromCenter = ((laneShit) - halfKeyCount) + offsetThing; // theres probably an easier way of doing this
		// basically
		// 0 = 1.5
		// 1 = 0.5
		// 2 = -0.5
		// 3 = -1.5
		// so if you then multiply by the arrow size, all notes should be in the same place
		noteData.x += -distFromCenter * NoteMovement.arrowSize;

		var upscroll = !isDownscroll();


		var q = SimpleQuaternion.fromEuler(subValues.get('z').value, subValues.get('x').value,
			(upscroll ? -subValues.get('y').value : subValues.get('y').value)); // i think this is the right order???
		// q = SimpleQuaternion.normalize(q); //dont think its too nessessary???
		noteData.x += q.x * distFromCenter * NoteMovement.arrowSize;
		noteData.y += q.y * distFromCenter * NoteMovement.arrowSize;
		noteData.z += q.z * distFromCenter * NoteMovement.arrowSize;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}

	override function reset() {
		super.reset();
		currentValue = 1.0;
	}
}

class BumpyModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.z += currentValue * 40 * Math.sin(curPos * 0.01 * (subValues.get('speed').value * states.PlayState.songMultiplier));
	}
}

class XModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.x += currentValue;
	}
}

class YModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.y += currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.y += currentValue;
	}
}

class ZModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.z += currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.z += currentValue;
	}
}

class PitchModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.angleX += currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.angleX += currentValue;
	}
}

class YawModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.angleY += currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.angleY += currentValue;
	}
}

class ConfusionModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.angleZ += currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.angleZ += currentValue;
	}
}

class ScaleModifier extends Modifier {
	override function setupSubValues() {
		baseValue = 1.0;
		currentValue = 1.0;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.scaleX *= currentValue;
		noteData.scaleY *= currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.scaleX *= currentValue;
		noteData.scaleY *= currentValue;
	}
}

class ScaleXModifier extends Modifier {
	override function setupSubValues() {
		baseValue = 1.0;
		currentValue = 1.0;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.scaleX *= currentValue;

	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.scaleX *= currentValue;

	}
}

class ScaleYModifier extends Modifier {
	override function setupSubValues() {
		baseValue = 1.0;
		currentValue = 1.0;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {

		noteData.scaleY *= currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {

		noteData.scaleY *= currentValue;
	}
}

class SpeedModifier extends Modifier {
	override function setupSubValues() {
		baseValue = 1.0;
		currentValue = 1.0;
	}

	override function curPosMath(lane:Int, curPos:Float, pf:Int) {
		return curPos * currentValue;
	}
}

class StealthModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.alpha *= 1 - currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}
}

class NoteStealthModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.alpha *= 1 - currentValue;
	}
}

class InvertModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += NoteMovement.arrowSizes[lane] * (lane % 2 == 0 ? 1 : -1) * currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}
}

class FlipModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var nd = lane % NoteMovement.keyCount;
		var newPos = FlxMath.remapToRange(nd, 0, NoteMovement.keyCount, NoteMovement.keyCount, -NoteMovement.keyCount);
		noteData.x += NoteMovement.arrowSizes[lane] * newPos * currentValue;
		noteData.x -= NoteMovement.arrowSizes[lane] * currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}
}

class MiniModifier extends Modifier {
	override function setupSubValues() {
		baseValue = 1.0;
		currentValue = 1.0;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var col = (lane % NoteMovement.keyCount);
		var daswitch = isDownscroll() ? -1 : 1;

		var midFix = isMiddlescroll();



		noteData.scaleX *= currentValue;
		noteData.scaleY *= currentValue;
		noteData.x -= ((NoteMovement.arrowSizes[lane] / 2) * (noteData.scaleX - NoteMovement.defaultScale[lane]));
		noteData.y += daswitch * ((NoteMovement.arrowSizes[lane] / 2) * (noteData.scaleY - NoteMovement.defaultScale[lane]));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}
}

class ShrinkModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var scaleMult = 1 + (curPos * 0.001 * currentValue);
		noteData.scaleX *= scaleMult;
		noteData.scaleY *= scaleMult;
	}
}

class BeatXModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += currentValue * getShift(noteData, lane, curPos, pf);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}

	public static function getShift(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int):Float {
		var fAccelTime = 0.2;
		var fTotalTime = 0.5;

		/* If the song is really fast, slow down the rate, but speed up the
		 * acceleration to compensate or it'll look weird. */
		// var fBPM = Conductor.bpm * 60;
		// var fDiv = Math.max(1.0, Math.floor( fBPM / 150.0 ));
		// fAccelTime /= fDiv;
		// fTotalTime /= fDiv;

		/* offset by VisualDelayEffect seconds */
		var fBeat = Modifier.beat + fAccelTime;
		// fBeat /= fDiv;

		var bEvenBeat = (Math.floor(fBeat) % 2) != 0;

		/* -100.2 -> -0.2 -> 0.2 */
		if (fBeat < 0)
			return 0;

		fBeat -= Math.floor(fBeat);
		fBeat += 1;
		fBeat -= Math.floor(fBeat);

		if (fBeat >= fTotalTime)
			return 0;

		var fAmount:Float;
		if (fBeat < fAccelTime) {
			fAmount = FlxMath.remapToRange(fBeat, 0.0, fAccelTime, 0.0, 1.0);
			fAmount *= fAmount;
		} else
			/* fBeat < fTotalTime */ {
			fAmount = FlxMath.remapToRange(fBeat, fAccelTime, fTotalTime, 1.0, 0.0);
			fAmount = 1 - (1 - fAmount) * (1 - fAmount);
		}

		if (bEvenBeat)
			fAmount *= -1;

		var fShift = 20.0 * fAmount * Math.sin((curPos * 0.01) + (Math.PI / 2.0));
		return fShift;
	}
}

class BeatYModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.y += currentValue * BeatXModifier.getShift(noteData, lane, curPos, pf);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}
}

class BeatZModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.z += currentValue * BeatXModifier.getShift(noteData, lane, curPos, pf);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}
}

class BounceXModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += currentValue * NoteMovement.arrowSizes[lane] * Math.abs(Math.sin(curPos * 0.005 * (subValues.get('speed').value * states.PlayState.songMultiplier)));
	}
}

class BounceYModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var daswitch = isDownscroll() ? -1 : 1;
		noteData.y += (currentValue * daswitch) * NoteMovement.arrowSizes[lane] * Math.abs(Math.sin(curPos * 0.005 * (subValues.get('speed').value * states.PlayState.songMultiplier)));
	}
}

class BounceZModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.z += currentValue * NoteMovement.arrowSizes[lane] * Math.abs(Math.sin(curPos * 0.005 * (subValues.get('speed').value * states.PlayState.songMultiplier)));
	}
}

class StrumBounceXModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('amplitude', new ModifierSubValue(45));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		strumMath(noteData, lane, pf);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.x += Math.abs(Math.sin(Modifier.beat * 3 * (subValues.get('speed').value * states.PlayState.songMultiplier))) * subValues.get('amplitude').value;
	}
}

class StrumBounceYModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('amplitude', new ModifierSubValue(45));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		strumMath(noteData, lane, pf);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.y -= Math.abs(Math.sin(Modifier.beat * 3 * (subValues.get('speed').value * states.PlayState.songMultiplier))) * subValues.get('amplitude').value;
	}
}

class StrumBounceZModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('amplitude', new ModifierSubValue(45));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		strumMath(noteData, lane, pf);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.z += Math.abs(Math.sin(Modifier.beat * 3 * (subValues.get('speed').value * states.PlayState.songMultiplier))) * subValues.get('amplitude').value;
	}
}

class HopModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		strumMath(noteData, lane, pf);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		var val = currentValue * (Note.swagWidth / 2);
		noteData.x += val * Math.sin((cast(FlxG.state, states.MusicBeatState).curDecStep / Conductor.timeScale[1]) * Math.PI) - val * 0.5;
		noteData.y -= val * 0.5 * Math.abs(Math.cos((cast(FlxG.state, states.MusicBeatState).curDecStep / Conductor.timeScale[1]) * Math.PI))
			- val * 0.25;
	}
}

class EaseCurveModifier extends Modifier {
	public var easeFunc = FlxEase.linear;

	public function setEase(ease:String) {
		easeFunc = ModchartUtil.getFlxEaseByString(ease);
	}
}

class EaseCurveXModifier extends EaseCurveModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += (easeFunc(curPos * 0.01) * currentValue * 0.2);
	}
}

class EaseCurveYModifier extends EaseCurveModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.y += (easeFunc(curPos * 0.01) * currentValue * 0.2);
	}
}

class EaseCurveZModifier extends EaseCurveModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.z += (easeFunc(curPos * 0.01) * currentValue * 0.2);
	}
}

class EaseCurveAngleModifier extends EaseCurveModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.angleZ += (easeFunc(curPos * 0.01) * currentValue * 0.2);
	}
}

class InvertSineModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += Math.sin(0 + (curPos * 0.004)) * (NoteMovement.arrowSizes[lane] * (lane % 2 == 0 ? 1 : -1) * currentValue * 0.5);
	}
}

class BoostModifier extends Modifier {
	override function curPosMath(lane:Int, curPos:Float, pf:Int) {
		var yOffset:Float = 0;

		var speed = renderer.getCorrectScrollSpeed();

		var fYOffset = -curPos / speed;
		var fEffectHeight = FlxG.height;
		var fNewYOffset = fYOffset * 1.5 / ((fYOffset + fEffectHeight / 1.2) / fEffectHeight);
		var fBrakeYAdjust = currentValue * (fNewYOffset - fYOffset);
		fBrakeYAdjust = FlxMath.bound(fBrakeYAdjust, -400, 400); // clamp

		yOffset -= fBrakeYAdjust * speed;

		return curPos + yOffset;
	}
}

class BrakeModifier extends Modifier {
	override function curPosMath(lane:Int, curPos:Float, pf:Int) {
		var yOffset:Float = 0;

		var speed = renderer.getCorrectScrollSpeed();

		var fYOffset = -curPos / speed;
		var fEffectHeight = FlxG.height;
		var fScale = FlxMath.remapToRange(fYOffset, 0, fEffectHeight, 0, 1); // scale
		var fNewYOffset = fYOffset * fScale;
		var fBrakeYAdjust = currentValue * (fNewYOffset - fYOffset);
		fBrakeYAdjust = FlxMath.bound(fBrakeYAdjust, -400, 400); // clamp

		yOffset -= fBrakeYAdjust * speed;

		return curPos + yOffset;
	}
}

class BoomerangModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var scrollSwitch = isDownscroll() ? 1 : -1;

		noteData.y += (Math.sin((curPos / -700)) * 400 + (curPos / 3.5)) * scrollSwitch * (-currentValue);
		noteData.alpha *= FlxMath.bound(1 - (curPos / -600 - 3.5), 0, 1);
	}

	override function curPosMath(lane:Int, curPos:Float, pf:Int) {
		return curPos * 0.75;
	}
}

class WaveingModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var distance = curPos * 0.01;
		noteData.y += (Math.sin(distance * 0.3) * 50) * currentValue; // don't mind me i just figured it out
	}

	override function noteDistMath(noteDist:Float, lane:Int, curPos:Float, pf:Int) {
		return noteDist * (0.4 + ((Math.sin(curPos * 0.007) * 0.1) * currentValue));
	}
}

class JumpModifier extends Modifier // custom thingy i made
{
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		strumMath(noteData, lane, pf);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		var beatVal = Modifier.beat - Math.floor(Modifier.beat); // should give decimal

		var scrollSwitch = isDownscroll() ? -1 : 1;

		noteData.y += (beatVal * (Conductor.stepCrochet * currentValue)) * renderer.getCorrectScrollSpeed() * 0.45 * scrollSwitch;
	}
}

class WaveXModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.x += 260 * currentValue * Math.sin(((Conductor.songPosition) * ((subValues.get('speed').value * states.PlayState.songMultiplier)) * 0.0008) + (lane / 4)) * 0.2;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		strumMath(noteData, lane, pf);
	}
}

class WaveYModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.y += 260 * currentValue * Math.sin(((Conductor.songPosition) * ((subValues.get('speed').value * states.PlayState.songMultiplier)) * 0.0008) + (lane / 4)) * 0.2;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		strumMath(noteData, lane, pf);
	}
}

class WaveZModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.z += 260 * currentValue * Math.sin(((Conductor.songPosition) * ((subValues.get('speed').value * states.PlayState.songMultiplier)) * 0.0008) + (lane / 4)) * 0.2;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		strumMath(noteData, lane, pf);
	}
}

class TimeStopModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('stop', new ModifierSubValue(0.0));
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('continue', new ModifierSubValue(0.0));
	}

	override function curPosMath(lane:Int, curPos:Float, pf:Int) {
		if (curPos <= (subValues.get('stop').value * -1000)) {
			curPos = (subValues.get('stop').value * -1000) + (curPos * ((subValues.get('speed').value * states.PlayState.songMultiplier) / 100));
		}
		return curPos;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		if (curPos <= (subValues.get('stop').value * -1000)) {
			curPos = (subValues.get('stop').value * -1000) + (curPos * ((subValues.get('speed').value * states.PlayState.songMultiplier) / 100));
		} else if (curPos <= (subValues.get('continue').value * -100)) {
		} else {
			// yep, nothing here lmao
		}
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class StrumAngleModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var multiply = isDownscroll() ? 1 : -1;
		noteData.angleZ += (currentValue * multiply);
		var laneShit = lane % NoteMovement.keyCount;
		var offsetThing = 0.5;
		var halfKeyCount = NoteMovement.keyCount / 2;
		if (lane < halfKeyCount) {
			offsetThing = -0.5;
			laneShit = lane + 1;
		}
		var distFromCenter = ((laneShit) - halfKeyCount) + offsetThing;
		noteData.x += -distFromCenter * NoteMovement.arrowSize;

		var q = SimpleQuaternion.fromEuler(90, 0, (currentValue * multiply)); // i think this is the right order???
		noteData.x += q.x * distFromCenter * NoteMovement.arrowSize;
		noteData.y += q.y * distFromCenter * NoteMovement.arrowSize;
		noteData.z += q.z * distFromCenter * NoteMovement.arrowSize;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {

		noteMath(noteData, lane, 0, pf);
	}

	override function incomingAngleMath(lane:Int, curPos:Float, pf:Int) {
		return [0, currentValue * -1];
	}

	override function reset() {
		super.reset();
		currentValue = 0; // the code that stop the mod from running gets confused when it resets in the editor i guess??
	}
}

class JumpTargetModifier extends Modifier {
	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		var beatVal = Modifier.beat - Math.floor(Modifier.beat); // should give decimal

		var scrollSwitch = isDownscroll() ? -1 : 1;

		noteData.y += (beatVal * (Conductor.stepCrochet * currentValue)) * renderer.getCorrectScrollSpeed() * 0.45 * scrollSwitch;
	}
}

class JumpNotesModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var beatVal = Modifier.beat - Math.floor(Modifier.beat); // should give decimal

		var scrollSwitch = isDownscroll() ? -1 : 1;

		noteData.y += (beatVal * (Conductor.stepCrochet * currentValue)) * renderer.getCorrectScrollSpeed() * 0.45 * scrollSwitch;
	}
}

class LaneStealthModifier extends Modifier {
	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.alpha *= 1 - currentValue;
	}
}

class EaseXModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += currentValue * (Math.cos(((Conductor.songPosition * 0.001) +
			((lane % NoteMovement.keyCount) * 0.2) * (10 / FlxG.height)) * (subValues.get('speed')
			.value * 0.2)) * Note.swagWidth * 0.5);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class EaseYModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.y += currentValue * (Math.cos(((Conductor.songPosition * 0.001) +
			((lane % NoteMovement.keyCount) * 0.2) * (10 / FlxG.height)) * (subValues.get('speed')
			.value * 0.2)) * Note.swagWidth * 0.5);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class EaseZModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.z += currentValue * (Math.cos(((Conductor.songPosition * 0.001) +
			((lane % NoteMovement.keyCount) * 0.2) * (10 / FlxG.height)) * (subValues.get('speed')
			.value * 0.2)) * Note.swagWidth * 0.5);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class XMModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var daswitch = 0;
		if (instance != null && (FlxG.state is ModchartEditorState ? cast(FlxG.state, ModchartEditorState).check_middlescroll.checked : isMiddlescroll()))
			daswitch = 1;
		noteData.x += currentValue * daswitch;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class YDModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var daswitch = isDownscroll() ? -1 : 1;
		noteData.y += currentValue * daswitch;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class SuddenModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('offset', new ModifierSubValue(0.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		if (curPos <= (subValues.get('offset').value * -100) && curPos >= ((subValues.get('offset').value * -100) - 200)) {
			var hmult = -(curPos - (subValues.get('offset').value * -100)) / 200;
			noteData.alpha *= (1 - hmult) * currentValue;
		} else if (curPos < ((subValues.get('offset').value * -100) - 100)) {
			noteData.alpha *= (1 - currentValue);
		}
	}
}

class HiddenModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('offset', new ModifierSubValue(0.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		if (curPos > ((subValues.get('offset').value * -100) - 100)) {
			var hmult = (curPos - (subValues.get('offset').value * -100)) / 200;
			noteData.alpha *= (1 - hmult);
		}
	}
}

class VanishModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('offsetIn', new ModifierSubValue(1.0));
		subValues.set('offsetOut', new ModifierSubValue(0.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		if (curPos <= (subValues.get('offsetOut').value * -100) && curPos >= ((subValues.get('offsetOut').value * -100) - 200)) {
			var hmult = -(curPos - (subValues.get('offsetOut').value * -100)) / 200;
			noteData.alpha *= (1 - hmult) * currentValue;
		} else if (curPos > ((subValues.get('offsetIn').value * -100) - 100)) {
			var hmult = (curPos - (subValues.get('offsetIn').value * -100)) / 200;
			noteData.alpha *= (1 - hmult);
		} else if (curPos < ((subValues.get('offsetOut').value * -100) - 100)) {
			noteData.alpha *= (1 - currentValue);
		}
	}
}

class SkewModifier extends Modifier {
	override function setupSubValues() {
		baseValue = 0.0;
		currentValue = 1.0;
		subValues.set('x', new ModifierSubValue(0.0));
		subValues.set('y', new ModifierSubValue(0.0));
		subValues.set('xDmod', new ModifierSubValue(0.0));
		subValues.set('yDmod', new ModifierSubValue(0.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var daswitch = isDownscroll() ? 1 : -1;

		noteData.skewX += subValues.get('x').value * daswitch;
		noteData.skewY += subValues.get('y').value * daswitch;

		noteData.skewX += subValues.get('xDmod').value * daswitch;
		noteData.skewY += subValues.get('yDmod').value * daswitch;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}

	override function reset() {
		super.reset();
		baseValue = 0.0;
		currentValue = 1.0;
	}
}

class SkewXModifier extends Modifier {
	override function setupSubValues() {
		baseValue = 0.0;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var daswitch = isDownscroll() ? 1 : -1;
		noteData.skewX += currentValue * daswitch;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}
}

class SkewYModifier extends Modifier {
	override function setupSubValues() {
		baseValue = 0.0;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var daswitch = isDownscroll() ? 1 : -1;
		noteData.skewY += currentValue * daswitch;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}
}

class DizzyModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.angleZ += currentValue * curPos;
	}
}

class NotesModifier extends Modifier {
	override function setupSubValues() {
		baseValue = 0.0;
		currentValue = 1.0;
		subValues.set('x', new ModifierSubValue(0.0));
		subValues.set('y', new ModifierSubValue(0.0));
		subValues.set('yD', new ModifierSubValue(0.0));
		subValues.set('angle', new ModifierSubValue(0.0));
		subValues.set('z', new ModifierSubValue(0.0));
		subValues.set('skewx', new ModifierSubValue(0.0));
		subValues.set('skewy', new ModifierSubValue(0.0));
		subValues.set('invert', new ModifierSubValue(0.0));
		subValues.set('flip', new ModifierSubValue(0.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var daswitch = isDownscroll() ? -1 : 1;

		noteData.x += subValues.get('x').value;
		noteData.y += subValues.get('y').value;
		noteData.y += subValues.get('yD').value * daswitch;
		noteData.angleZ += subValues.get('angle').value;
		noteData.z += subValues.get('z').value;
		noteData.skewX += subValues.get('skewx').value * -daswitch;
		noteData.skewY += subValues.get('skewy').value * -daswitch;

		noteData.x += NoteMovement.arrowSizes[lane] * (lane % 2 == 0 ? 1 : -1) * subValues.get('invert').value;

		var nd = lane % NoteMovement.keyCount;
		var newPos = FlxMath.remapToRange(nd, 0, NoteMovement.keyCount, NoteMovement.keyCount, -NoteMovement.keyCount);
		noteData.x += NoteMovement.arrowSizes[lane] * newPos * subValues.get('flip').value;
		noteData.x -= NoteMovement.arrowSizes[lane] * subValues.get('flip').value;
	}

	override function reset() {
		super.reset();
		baseValue = 0.0;
		currentValue = 1.0;
	}
}

class LanesModifier extends Modifier {
	override function setupSubValues() {
		baseValue = 0.0;
		currentValue = 1.0;
		subValues.set('x', new ModifierSubValue(0.0));
		subValues.set('y', new ModifierSubValue(0.0));
		subValues.set('yD', new ModifierSubValue(0.0));
		subValues.set('angle', new ModifierSubValue(0.0));
		subValues.set('z', new ModifierSubValue(0.0));
		subValues.set('skewx', new ModifierSubValue(0.0));
		subValues.set('skewy', new ModifierSubValue(0.0));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		var daswitch = isDownscroll() ? -1 : 1;

		noteData.x += subValues.get('x').value;
		noteData.y += subValues.get('y').value;
		noteData.y += subValues.get('yD').value * daswitch;
		noteData.angleZ += subValues.get('angle').value;
		noteData.z += subValues.get('z').value;
		noteData.skewX += subValues.get('skewx').value * -daswitch;
		noteData.skewY += subValues.get('skewy').value * -daswitch;
	}

	override function reset() {
		super.reset();
		baseValue = 0.0;
		currentValue = 1.0;
	}
}

class StrumsModifier extends Modifier {
	override function setupSubValues() {
		baseValue = 0.0;
		currentValue = 1.0;
		subValues.set('x', new ModifierSubValue(0.0));
		subValues.set('y', new ModifierSubValue(0.0));
		subValues.set('yD', new ModifierSubValue(0.0));
		subValues.set('angle', new ModifierSubValue(0.0));
		subValues.set('z', new ModifierSubValue(0.0));
		subValues.set('skewx', new ModifierSubValue(0.0));
		subValues.set('skewy', new ModifierSubValue(0.0));
		subValues.set('invert', new ModifierSubValue(0.0));
		subValues.set('flip', new ModifierSubValue(0.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var daswitch = isDownscroll() ? -1 : 1;

		noteData.x += subValues.get('x').value;
		noteData.y += subValues.get('y').value;
		noteData.y += subValues.get('yD').value * daswitch;
		noteData.angleZ += subValues.get('angle').value;
		noteData.z += subValues.get('z').value;
		noteData.skewX += subValues.get('skewx').value * -daswitch;
		noteData.skewY += subValues.get('skewy').value * -daswitch;

		noteData.x += NoteMovement.arrowSizes[lane] * (lane % 2 == 0 ? 1 : -1) * subValues.get('invert').value;

		var nd = lane % NoteMovement.keyCount;
		var newPos = FlxMath.remapToRange(nd, 0, NoteMovement.keyCount, NoteMovement.keyCount, -NoteMovement.keyCount);
		noteData.x += NoteMovement.arrowSizes[lane] * newPos * subValues.get('flip').value;
		noteData.x -= NoteMovement.arrowSizes[lane] * subValues.get('flip').value;
	}

	override function reset() {
		super.reset();
		baseValue = 0.0;
		currentValue = 1.0;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}
}

class TanDrunkXModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('period', new ModifierSubValue(1.0));
		subValues.set('offset', new ModifierSubValue(1.0));
		subValues.set('spacing', new ModifierSubValue(1.0));
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('size', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += currentValue * (Math.tan(((Conductor.songPosition * (0.001 * subValues.get('period').value))
			+ ((lane % NoteMovement.keyCount) * 0.2)
			+ (curPos * (0.225 * subValues.get('offset')
				.value)) * ((subValues.get('spacing')
					.value * 10) / FlxG.height)) * ((subValues.get('speed').value * states.PlayState.songMultiplier) * 0.2)) * Note.swagWidth * (0.5 * subValues.get('size').value));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class TanDrunkYModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('period', new ModifierSubValue(1.0));
		subValues.set('offset', new ModifierSubValue(1.0));
		subValues.set('spacing', new ModifierSubValue(1.0));
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('size', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.y += currentValue * (Math.tan(((Conductor.songPosition * (0.001 * subValues.get('period').value))
			+ ((lane % NoteMovement.keyCount) * 0.2)
			+ (curPos * (0.225 * subValues.get('offset')
				.value)) * ((subValues.get('spacing')
					.value * 10) / FlxG.height)) * ((subValues.get('speed').value * states.PlayState.songMultiplier) * 0.2)) * Note.swagWidth * (0.5 * subValues.get('size').value));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class TanDrunkZModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('period', new ModifierSubValue(1.0));
		subValues.set('offset', new ModifierSubValue(1.0));
		subValues.set('spacing', new ModifierSubValue(1.0));
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('size', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.z += currentValue * (Math.tan(((Conductor.songPosition * (0.001 * subValues.get('period').value))
			+ ((lane % NoteMovement.keyCount) * 0.2)
			+ (curPos * (0.225 * subValues.get('offset')
				.value)) * ((subValues.get('spacing')
					.value * 10) / FlxG.height)) * ((subValues.get('speed').value * states.PlayState.songMultiplier) * 0.2)) * Note.swagWidth * (0.5 * subValues.get('size').value));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class TanWaveXModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.x += 260 * currentValue * Math.tan(((Conductor.songPosition) * ((subValues.get('speed').value * states.PlayState.songMultiplier)) * 0.0008) + (lane / 4)) * 0.2;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		strumMath(noteData, lane, pf);
	}
}

class TanWaveYModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.y += 260 * currentValue * Math.tan(((Conductor.songPosition) * ((subValues.get('speed').value * states.PlayState.songMultiplier)) * 0.0008) + (lane / 4)) * 0.2;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		strumMath(noteData, lane, pf);
	}
}

class TanWaveZModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.z += 260 * currentValue * Math.tan(((Conductor.songPosition) * ((subValues.get('speed').value * states.PlayState.songMultiplier)) * 0.0008) + (lane / 4)) * 0.2;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		strumMath(noteData, lane, pf);
	}
}

class BlinkModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.alpha *= (1 - (currentValue * Math.sin(((Conductor.songPosition * 0.001) * ((subValues.get('speed').value * states.PlayState.songMultiplier) * 10)))));
	}
}

class TwirlModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.scaleX *= (0 + (currentValue * Math.cos(((curPos * 0.001) * (5 * (subValues.get('speed').value * states.PlayState.songMultiplier))))));
	}
}

class RollModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.scaleY *= (0 + (currentValue * Math.cos(((curPos * 0.001) * (5 * (subValues.get('speed').value * states.PlayState.songMultiplier))))));
	}
}

class CosecantXModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('period', new ModifierSubValue(1.0));
		subValues.set('offset', new ModifierSubValue(1.0));
		subValues.set('spacing', new ModifierSubValue(1.0));
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('size', new ModifierSubValue(1.0));
	}

	public static function cosecant(angle:Null<Float>):Float {
		return 1 / Math.sin(angle);
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += currentValue * (cosecant(((Conductor.songPosition * (0.001 * subValues.get('period').value))
			+ ((lane % NoteMovement.keyCount) * 0.2)
			+ (curPos * (0.225 * subValues.get('offset')
				.value)) * ((subValues.get('spacing')
					.value * 10) / FlxG.height)) * ((subValues.get('speed').value * states.PlayState.songMultiplier) * 0.2)) * Note.swagWidth * (0.5 * subValues.get('size').value));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class CosecantYModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('period', new ModifierSubValue(1.0));
		subValues.set('offset', new ModifierSubValue(1.0));
		subValues.set('spacing', new ModifierSubValue(1.0));
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('size', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.y += currentValue * (CosecantXModifier.cosecant(((Conductor.songPosition * (0.001 * subValues.get('period').value))
			+ ((lane % NoteMovement.keyCount) * 0.2)
			+ (curPos * (0.225 * subValues.get('offset')
				.value)) * ((subValues.get('spacing')
					.value * 10) / FlxG.height)) * ((subValues.get('speed').value * states.PlayState.songMultiplier) * 0.2)) * Note.swagWidth * (0.5 * subValues.get('size').value));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class CosecantZModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('period', new ModifierSubValue(1.0));
		subValues.set('offset', new ModifierSubValue(1.0));
		subValues.set('spacing', new ModifierSubValue(1.0));
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('size', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.z += currentValue * (CosecantXModifier.cosecant(((Conductor.songPosition * (0.001 * subValues.get('period').value))
			+ ((lane % NoteMovement.keyCount) * 0.2)
			+ (curPos * (0.225 * subValues.get('offset')
				.value)) * ((subValues.get('spacing')
					.value * 10) / FlxG.height)) * ((subValues.get('speed').value * states.PlayState.songMultiplier) * 0.2)) * Note.swagWidth * (0.5 * subValues.get('size').value));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class WaveAngleModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.angleZ += 260 * currentValue * Math.sin(((Conductor.songPosition) * ((subValues.get('speed').value * states.PlayState.songMultiplier)) * 0.0008) + (lane / 4)) * 0.2;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		strumMath(noteData, lane, pf);
	}
}

class TanWaveAngleModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.angleZ += 260 * currentValue * Math.tan(((Conductor.songPosition) * ((subValues.get('speed').value * states.PlayState.songMultiplier)) * 0.0008) + (lane / 4)) * 0.2;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		strumMath(noteData, lane, pf);
	}
}

class DrunkAngleModifier extends DrunkXModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.angleZ += drunkMath(noteData, lane, curPos, pf);
	}
}

class DrunkPitchModifier extends DrunkXModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.angleX += drunkMath(noteData, lane, curPos, pf);
	}
}

class DrunkYawModifier extends DrunkXModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.angleY += drunkMath(noteData, lane, curPos, pf);
	}
}

class TanDrunkAngleModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('period', new ModifierSubValue(1.0));
		subValues.set('offset', new ModifierSubValue(1.0));
		subValues.set('spacing', new ModifierSubValue(1.0));
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('size', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.angleZ += currentValue * (Math.tan(((Conductor.songPosition * (0.001 * subValues.get('period').value))
			+ ((lane % NoteMovement.keyCount) * 0.2)
			+ (curPos * (0.225 * subValues.get('offset')
				.value)) * ((subValues.get('spacing')
					.value * 10) / FlxG.height)) * ((subValues.get('speed').value * states.PlayState.songMultiplier) * 0.2)) * Note.swagWidth * (0.5 * subValues.get('size').value));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf); // just reuse same thing
	}
}

class ShakyNotesModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += Math.sin(500)
			+ currentValue * (Math.cos(Conductor.songPosition * 4 * 0.2) + ((lane % NoteMovement.keyCount) * 0.2) - 0.002) * (Math.sin(100
				- (120 * (subValues.get('speed').value * states.PlayState.songMultiplier) * 0.4)));

		noteData.y += Math.sin(500)
			+ currentValue * (Math.cos(Conductor.songPosition * 8 * 0.2) + ((lane % NoteMovement.keyCount) * 0.2) - 0.002) * (Math.sin(100
				- (120 * (subValues.get('speed').value * states.PlayState.songMultiplier) * 0.4)));
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}
}

class ShakeNotesModifier extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var shake = Math.sin(Conductor.songPosition * 0.01 + curPos * 0.1) * currentValue * 10;
		noteData.x += shake;
		noteData.y += shake;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteMath(noteData, lane, 0, pf);
	}
}

class TordnadoModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		// thank you 4mbr0s3 & andromeda for the modifier lol -- LETS GOOOO FINALLY I FIGURED IT OUT
		var playerColumn = lane % NoteMovement.keyCount;
		var columnPhaseShift = playerColumn * Math.PI / 3;
		var phaseShift = (curPos / 135) * (subValues.get('speed').value * states.PlayState.songMultiplier) * 0.2;
		var returnReceptorToZeroOffsetX = (-Math.cos(-columnPhaseShift) + 1) / 2 * Note.swagWidth * 3;
		var offsetX = (-Math.cos((phaseShift - columnPhaseShift)) + 1) / 2 * Note.swagWidth * 3 - returnReceptorToZeroOffsetX;

		noteData.x += offsetX * currentValue;
	}
}

// troll engine modifiers ported

class ZigZagModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('offset', new ModifierSubValue(0.0));
		subValues.set('period', new ModifierSubValue(1.0));
	}

	inline public static function triangle(angle:Float) {
		var fAngle:Float = angle % (Math.PI * 2.0);
		if (fAngle < 0.0)
			fAngle += Math.PI * 2.0;

		var result:Float = fAngle / Math.PI;

		if (result < 0.5) {
			return 2.0 * result;
		} else if (result < 1.5) {
			return -2.0 * result + 2.0;
		} else {
			return 2.0 * result - 4.0;
		}
	}


	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var offset = subValues.get('offset').value;
		var period = subValues.get('period').value;
		var result:Float = 1;
		result = triangle((Math.PI * (1 / (period + 1)) * ((curPos + 100 * offset) / Note.swagWidth)));

		noteData.x += (currentValue * Note.swagWidth / 2) * result;
	}

	inline function mod(a:Float, b:Float):Float {
		return (a / b);
	}
}

class SquareModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('offset', new ModifierSubValue(0.0));
		subValues.set('period', new ModifierSubValue(1.0));
	}

	inline public static function square(angle:Float) {
		var fAngle = angle % (Math.PI * 2);

		return fAngle >= Math.PI ? -1.0 : 1.0;
	}

	inline public static function triangle(angle:Float) {
		var fAngle:Float = angle % (Math.PI * 2.0);
		if (fAngle < 0.0)
			fAngle += Math.PI * 2.0;

		var result:Float = fAngle / Math.PI;

		if (result < 0.5) {
			return 2.0 * result;
		} else if (result < 1.5) {
			return -2.0 * result + 2.0;
		} else {
			return 2.0 * result - 4.0;
		}
	}


	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var offset = subValues.get('offset').value;
		var period = subValues.get('period').value;
		var cum = (Math.PI * (curPos + offset) / (Note.swagWidth + (period * Note.swagWidth)));

		noteData.x += currentValue * Note.swagWidth / 2 * square(cum);
	}
}

class DigitalModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('steps', new ModifierSubValue(0.0));
		subValues.set('period', new ModifierSubValue(1.0));
		subValues.set('offset', new ModifierSubValue(0.0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var steps = subValues.get('steps').value + 1;
		var period = subValues.get('period').value;
		var offset = subValues.get('offset').value;

		noteData.x += (currentValue * Note.swagWidth / 2) * Math.floor(0.5 + (steps * Math.sin(getDigitalAngle(curPos, offset, period)))) / steps;
	}

	inline function getDigitalAngle(yOffset:Float, offset:Float, period:Float) {
		return Math.PI * (yOffset + (1 * offset)) / (Note.swagWidth + (period * Note.swagWidth));
	}
}

class SawtoothModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('period', new ModifierSubValue(0));
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var period = subValues.get('period').value + 1;
		var p = (0.5 / period * curPos) / Note.swagWidth;

		noteData.x += (currentValue * Note.swagWidth) * (p - Math.floor(p));
	}
}



class WiggleXModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(Math.PI * 3));
		subValues.set('holds', new ModifierSubValue(0));
	}

	inline function wiggleMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var extra:Float = 0;
		if (renderer != null && renderer.notes != null && noteData.index >= 0 && noteData.index < renderer.notes.members.length) {
			var n = renderer.notes.members[noteData.index];
			if (n != null && n.isSustainNote)
				extra = subValues.get('holds').value;
		}
		return Math.sin((curPos / FlxG.height) * subValues.get('speed')
			.value) * ((currentValue + extra) * 250);
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += wiggleMath(noteData, lane, curPos, pf);
	}


}

class WiggleYModifier extends WiggleXModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.y += wiggleMath(noteData, lane, curPos, pf);
	}


}

class WiggleZModifier extends WiggleXModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.z += wiggleMath(noteData, lane, curPos, pf);
	}


}
// OH MY FUCKING GOD, thanks to @noamlol for the code of this thing//
class ArrowPath extends Modifier {
	public var _path:List<TimeVector> = null;
	public var _pathDistance:Float = 0;

	override public function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		#if PSYCH
		if (Paths.fileExists("data/" + Paths.formatToSongPath(PlayState.SONG.song) + "/customMods/path.txt", TEXT))
		#elseif LEATHER
		if (openfl.utils.Assets.exists(Paths.txt(PlayState.SONG.song.toLowerCase() + "/customMods/path")))
		#end
		{
			var newPosition = executePath(0, curPos, lane, lane < 4 ? 0 : 1, new Vector4(noteData.x, noteData.y, noteData.z, 0));
			noteData.x = newPosition.x;
			noteData.y = newPosition.y;
			noteData.z = newPosition.z;
		}
	}

	override function setupSubValues() {
		subValues.set('x', new ModifierSubValue(0.0));
		subValues.set('y', new ModifierSubValue(0.0));
		currentValue = 1.0;
	}

	override function incomingAngleMath(lane:Int, curPos:Float, pf:Int) {
		return [subValues.get('x').value, subValues.get('y').value];
	}

	override function reset() {
		super.reset();
		currentValue = 1.0; // the code that stop the mod from running gets confused when it resets in the editor i guess??
	}

	public function loadPath() {
		var file = null;
		file = CoolUtil.coolTextFile(Paths #if PSYCH .modFolders #else .txt #end
			(#if PSYCH "data/" + #end PlayState.SONG.song.toLowerCase() + "/customMods/path" #if PSYCH + ".txt" #end));
		@:privateAccess
		var file2 = null;
		file2 = CoolUtil.coolTextFile(#if (PSYCH && PSYCHVERSION >= "0.7.3") Paths.getSharedPath #else Paths.getPreloadPath #end
			("data/" + PlayState.SONG.song.toLowerCase() + "/customMods/path.txt"));

		var filePath = null;
		if (file != null) {
			filePath = file;
		} else if (file2 != null) {
			filePath = file2;
		} else {
			return;
		}

		// trace(filePath);

		var path = new List<TimeVector>();
		var _g = 0;
		while (_g < filePath.length) {
			var line = filePath[_g];
			_g++;
			var coords = line.split(";");
			var vec = new TimeVector(Std.parseFloat(coords[0]), Std.parseFloat(coords[1]), Std.parseFloat(coords[2]), Std.parseFloat(coords[3]));
			vec.x *= 200;
			vec.y *= 200;
			vec.z *= 200;
			path.add(vec);
			// trace(coords);
		}
		_pathDistance = calculatePathDistances(path);
		_path = path;
	}

	public function calculatePathDistances(path:List<TimeVector>):Float {
		@:privateAccess
		var iterator_head = path.h;
		var val = iterator_head.item;
		iterator_head = iterator_head.next;
		var last = val;
		last.startDist = 0;
		var dist = 0.0;
		while (iterator_head != null) {
			var val = iterator_head.item;
			iterator_head = iterator_head.next;
			var current = val;
			var result = new Vector4();
			result.x = current.x - last.x;
			result.y = current.y - last.y;
			result.z = current.z - last.z;
			var differential = result;
			dist += Math.sqrt(differential.x * differential.x + differential.y * differential.y + differential.z * differential.z);
			current.startDist = dist;
			last.next = current;
			last.endDist = current.startDist;
			last = current;
		}
		return dist;
	}

	public function getPointAlongPath(distance:Float):TimeVector {
		@:privateAccess
		var _g_head = this._path.h;
		while (_g_head != null) {
			var val = _g_head.item;
			_g_head = _g_head.next;
			var vec = val;
			var Min = vec.startDist;
			var Max = vec.endDist;
			// looks like a FlxMath function could be that
			if ((Min == 0 || distance >= Min) && (Max == 0 || distance <= Max) && vec.next != null) {
				var ratio = distance - vec.startDist;
				var _this = vec.next;
				var result = new Vector4();
				result.x = _this.x - vec.x;
				result.y = _this.y - vec.y;
				result.z = _this.z - vec.z;
				var ratio1 = ratio / Math.sqrt(result.x * result.x + result.y * result.y + result.z * result.z);
				var vec2 = vec.next;
				var out1 = new Vector4(vec.x, vec.y, vec.z, vec.w);
				var s = 1 - ratio1;
				out1.x *= s;
				out1.y *= s;
				out1.z *= s;
				var out2 = new Vector4(vec2.x, vec2.y, vec2.z, vec2.w);
				out2.x *= ratio1;
				out2.y *= ratio1;
				out2.z *= ratio1;
				var result1 = new Vector4();
				result1.x = out1.x + out2.x;
				result1.y = out1.y + out2.y;
				result1.z = out1.z + out2.z;
				return new TimeVector(result1.x, result1.y, result1.z, result1.w);
			}
		}
		return _path.first();
	}

	// var strumTimeDiff = Conductor.songPosition - note.strumTime;     -- saw this in the Groovin.js
	public function executePath(currentBeat, strumTimeDiff:Float, column, player, pos):Vector4 {
		if (_path == null) {
			loadPath();
		}
		var path = getPointAlongPath(strumTimeDiff / -1500.0 * _pathDistance);
		var a = new Vector4(FlxG.width / 2, FlxG.height / 2 + 280, column % 4 * getOtherPercent("arrowshapeoffset", player) + pos.z);
		var result = new Vector4();
		result.x = path.x + a.x;
		result.y = path.y + a.y;
		result.z = path.z + a.z;
		var vec2 = result;
		var lerp = getPercent(player);
		var out1 = new Vector4(pos.x, pos.y, pos.z, pos.w);
		var s = 1 - lerp;
		out1.x *= s;
		out1.y *= s;
		out1.z *= s;
		var out2 = new Vector4(vec2.x, vec2.y, vec2.z, vec2.w);
		out2.x *= lerp;
		out2.y *= lerp;
		out2.z *= lerp;
		var result = new Vector4();
		result.x = out1.x + out2.x;
		result.y = out1.y + out2.y;
		result.z = out1.z + out2.z;
		return result;
	}

	public function getPercent(player:Int):Float {
		return 1;
	}

	public function getOtherPercent(modName:String, player:Int):Float {
		return 1;
	}
}

class ColorTransformRed extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.redOffset += currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.redOffset += currentValue;
	}
}

class ColorTransformGreen extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.greenOffset += currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.greenOffset += currentValue;
	}
}

class ColorTransformBlue extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.blueOffset += currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.blueOffset += currentValue;
	}
}

class ColorTransformRainbowModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('spread', new ModifierSubValue(35.0));
	}

	function getRainbowColor(lane:Int, curPos:Float):FlxColor {
		var songMult = states.PlayState.songMultiplier;
		if (songMult == 0) songMult = 1.0;
		var spd = subValues.get('speed').value * songMult;
		var spread = subValues.get('spread').value;
		var hue = ((Conductor.songPosition * 0.001 * spd * 180.0) + (lane * spread)) % 360.0;
		if (hue < 0) hue += 360.0;
		return FlxColor.fromHSB(hue, 1.0, 1.0);
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		if (currentValue == 0) return;
		var mult = (currentValue > 1.0) ? (currentValue / 255.0) : currentValue;
		var col = getRainbowColor(lane, curPos);
		noteData.redOffset += col.red * mult;
		noteData.greenOffset += col.green * mult;
		noteData.blueOffset += col.blue * mult;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		if (currentValue == 0) return;
		var mult = (currentValue > 1.0) ? (currentValue / 255.0) : currentValue;
		var col = getRainbowColor(lane, 0);
		noteData.redOffset += col.red * mult;
		noteData.greenOffset += col.green * mult;
		noteData.blueOffset += col.blue * mult;
	}
}
class ColorTransformRainbow extends ColorTransformRainbowModifier {}

class ColorFillRed extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.hasColorFill = true;
		noteData.colorFillR += currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.hasColorFill = true;
		noteData.colorFillR += currentValue;
	}
}

class ColorFillGreen extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.hasColorFill = true;
		noteData.colorFillG += currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.hasColorFill = true;
		noteData.colorFillG += currentValue;
	}
}

class ColorFillBlue extends Modifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.hasColorFill = true;
		noteData.colorFillB += currentValue;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.hasColorFill = true;
		noteData.colorFillB += currentValue;
	}
}

class ColorFillAlpha extends Modifier {
	override public function getNotePath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteMath(noteData, lane, curPos, pf);
	}

	override public function getStrumPath(noteData:NotePositionData, lane:Int, pf:Int) {
		strumMath(noteData, lane, pf);
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.hasColorFill = true;
		noteData.colorFillAlpha = currentValue;
		noteData.colorFillAlphaExplicit = true;
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		noteData.hasColorFill = true;
		noteData.colorFillAlpha = currentValue;
		noteData.colorFillAlphaExplicit = true;
	}
}

class ColorFillModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('r', new ModifierSubValue(0.0));
		subValues.set('g', new ModifierSubValue(0.0));
		subValues.set('b', new ModifierSubValue(0.0));
		subValues.set('alpha', new ModifierSubValue(1.0));
	}

	override public function getNotePath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteMath(noteData, lane, curPos, pf);
	}

	override public function getStrumPath(noteData:NotePositionData, lane:Int, pf:Int) {
		strumMath(noteData, lane, pf);
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		applyColorFill(noteData);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		applyColorFill(noteData);
	}

	function applyColorFill(noteData:NotePositionData):Void {
		var a = subValues.get('alpha').value;
		var r = subValues.get('r').value;
		var g = subValues.get('g').value;
		var b = subValues.get('b').value;

		if (currentValue == baseValue && r == 0 && g == 0 && b == 0) return;
		if (a <= 0) {
			noteData.colorFillAlpha = 0;
			noteData.colorFillAlphaExplicit = true;
			return;
		}

		var finalAlpha = (currentValue != baseValue) ? (currentValue * a) : a;
		if (finalAlpha <= 0) {
			noteData.colorFillAlpha = 0;
			noteData.colorFillAlphaExplicit = true;
			return;
		}

		noteData.hasColorFill = true;
		noteData.colorFillR += r;
		noteData.colorFillG += g;
		noteData.colorFillB += b;
		noteData.colorFillAlpha = finalAlpha;
		noteData.colorFillAlphaExplicit = true;
	}
}

class ColorFillRainbowModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('spread', new ModifierSubValue(35.0));
		subValues.set('alpha', new ModifierSubValue(1.0));
	}

	function getRainbowColor(lane:Int, curPos:Float):FlxColor {
		var songMult = states.PlayState.songMultiplier;
		if (songMult == 0) songMult = 1.0;
		var spd = subValues.get('speed').value * songMult;
		var spread = subValues.get('spread').value;
		var hue = ((Conductor.songPosition * 0.001 * spd * 180.0) + (lane * spread)) % 360.0;
		if (hue < 0) hue += 360.0;
		return FlxColor.fromHSB(hue, 1.0, 1.0);
	}

	override public function getNotePath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		if (currentValue != baseValue) {
			noteMath(noteData, lane, curPos, pf);
		}
	}

	override public function getStrumPath(noteData:NotePositionData, lane:Int, pf:Int) {
		if (currentValue != baseValue) {
			strumMath(noteData, lane, pf);
		}
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		applyColorFillRainbow(noteData, lane, curPos);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		applyColorFillRainbow(noteData, lane, 0);
	}

	function applyColorFillRainbow(noteData:NotePositionData, lane:Int, curPos:Float):Void {
		var a = subValues.get('alpha').value;
		if (a <= 0 || currentValue <= 0) return;

		var fillAlpha:Float = currentValue * a;
		var col = getRainbowColor(lane, curPos);
		noteData.hasColorFill = true;
		noteData.colorFillR += col.red;
		noteData.colorFillG += col.green;
		noteData.colorFillB += col.blue;
		noteData.colorFillAlpha = fillAlpha;
		noteData.colorFillAlphaExplicit = true;
	}
}
class ColorFillRainbow extends ColorFillRainbowModifier {}

class SpiralXModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('spacing', new ModifierSubValue(0.0));
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('offset', new ModifierSubValue(0.0));
	}

	function spiral(oteData:NotePositionData, lane:Int, curPos:Float, pf:Int, func:Float->Float):Float {
		var dist = subValues.get('spacing').value * 33.5;
		var beat = (((subValues.get('speed').value * states.PlayState.songMultiplier) * cast(FlxG.state, states.MusicBeatState).curDecBeat) + (subValues.get('offset').value)) * Math.PI / 4;
		var radiusOffset = -curPos / 4;
		var radius = radiusOffset + dist * lane % NoteMovement.keyCount;

		return func(-curPos / Conductor.crochet * Math.PI + beat) * radius * currentValue;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.x += spiral(noteData, lane, curPos, pf, Math.cos);
	}
}

class SpiralYModifier extends SpiralXModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.y += spiral(noteData, lane, curPos, pf, Math.sin);
	}
}

class SpiralZModifier extends SpiralXModifier {
	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		noteData.z += spiral(noteData, lane, curPos, pf, Math.sin);
	}
}

class RingModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('amplitude', new ModifierSubValue(100.0));
	}

	function ringMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		var phase = (lane / NoteMovement.totalKeyCount) * Math.PI * 2;
		var angle = phase + (Conductor.songPosition * 0.001 * (subValues.get('speed').value * states.PlayState.songMultiplier));
		var amp = subValues.get('amplitude').value;

		noteData.x += Math.cos(angle) * amp * currentValue;
		noteData.z += Math.sin(angle) * amp * currentValue;
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		ringMath(noteData, lane, curPos, pf);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		ringMath(noteData, lane, 0, pf);
	}
}

class TrailModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('segments', new ModifierSubValue(4.0));
		subValues.set('spacing', new ModifierSubValue(15.0));
		subValues.set('speed', new ModifierSubValue(1.0));
		subValues.set('alpha', new ModifierSubValue(0.6));
	}

	override function gatherExtraNoteData(pf:Int):Array<NotePositionData> {
		if (currentValue == baseValue || renderer == null) return null;

		var extra:Array<NotePositionData> = [];
		var segCount = Std.int(Math.max(subValues.get('segments').value, 1));
		var spacing = subValues.get('spacing').value;
		var alphaStart = subValues.get('alpha').value;
		var maxDist = 2000.0;

		for (i in 0...renderer.notes.members.length) {
			var daNote = renderer.notes.members[i];
			if (daNote == null) continue;
			var lane = renderer.getLane(i);
			if (!checkLane(lane) || !checkPlayField(pf)) continue;

			var curPos = renderer.getNoteCurPos(i);
			curPos = renderer.modifierTable.applyCurPosMods(lane, curPos, pf);

			if ((daNote.wasGoodHit || (daNote.prevNote != null && daNote.prevNote.wasGoodHit)) && curPos >= 0 && daNote.isSustainNote)
				curPos = 0;

			if (Math.abs(curPos) > maxDist) continue;

			var noteDist = renderer.getNoteDist(i);
			noteDist = renderer.modifierTable.applyNoteDistMods(noteDist, lane, pf);

			var incomingAngle = renderer.modifierTable.applyIncomingAngleMods(lane, curPos, pf);
			if (noteDist < 0) incomingAngle[0] += 180;

			var origX = daNote.x;
			var origY = daNote.y;

			for (s in 0...segCount) {
				var trailCurPos = curPos - spacing * (s + 1) * currentValue;
				NoteMovement.setNotePath(daNote, lane, daNote.speed, trailCurPos, noteDist, incomingAngle[0], incomingAngle[1]);

				var trailData = renderer.createDataFromNote(i, pf, trailCurPos, noteDist, incomingAngle, daNote);
				renderer.modifierTable.applyNoteMods(trailData, lane, trailCurPos, pf);
				trailData.alpha *= alphaStart * (1 - (s / segCount));
				extra.push(trailData);
			}

			daNote.x = origX;
			daNote.y = origY;
		}
		return extra;
	}
}

class CopySpriteModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('amount', new ModifierSubValue(1.0)); // cantidad por defecto 1
		subValues.set('offsetX', new ModifierSubValue(0.0));
		subValues.set('offsetY', new ModifierSubValue(-50.0)); // arriba del strum por defecto
		subValues.set('offsetZ', new ModifierSubValue(0.0));
		subValues.set('offset', new ModifierSubValue(1.0)); // multiplicador general de offset
		subValues.set('speed', new ModifierSubValue(1.0)); // velocidad de desplazamiento/trail
		subValues.set('fadeSpeed', new ModifierSubValue(1.0)); // velocidad a la que se desvanece hasta destruirse
		subValues.set('alpha', new ModifierSubValue(0.8)); // opacidad de la copia
		subValues.set('hitWindow', new ModifierSubValue(180.0)); // proximidad al strum para activarse
	}

	override function gatherExtraNoteData(pf:Int):Array<NotePositionData> {
		if (currentValue == baseValue || renderer == null) return null;

		var extra:Array<NotePositionData> = [];
		var amountVal:Float = 1.0;
		if (subValues.exists('amount'))
			amountVal = subValues.get('amount').value;
		else if (subValues.exists('count'))
			amountVal = subValues.get('count').value;
		else if (subValues.exists('cantidad'))
			amountVal = subValues.get('cantidad').value;

		var copyCount = Std.int(Math.max(amountVal, 1));
		var offX = subValues.exists('offsetX') ? subValues.get('offsetX').value : 0.0;
		var offY = subValues.exists('offsetY') ? subValues.get('offsetY').value : -50.0;
		var offZ = subValues.exists('offsetZ') ? subValues.get('offsetZ').value : 0.0;
		var offsetMult = subValues.exists('offset') ? subValues.get('offset').value : 1.0;
		var speedVal = subValues.exists('speed') ? subValues.get('speed').value : 1.0;
		var fadeSpeedVal = subValues.exists('fadeSpeed') ? subValues.get('fadeSpeed').value : 1.0;
		var alphaVal = subValues.exists('alpha') ? subValues.get('alpha').value : 0.8;
		var hitWindow = subValues.exists('hitWindow') ? subValues.get('hitWindow').value : 180.0;

		var baseOffsetY = offY;
		if (isDownscroll() && offY == -50.0) {
			baseOffsetY = 50.0;
		}

		for (i in 0...renderer.notes.members.length) {
			var daNote = renderer.notes.members[i];
			if (daNote == null) continue;
			var lane = renderer.getLane(i);
			if (!checkLane(lane) || !checkPlayField(pf)) continue;

			var curPos = renderer.getNoteCurPos(i);
			curPos = renderer.modifierTable.applyCurPosMods(lane, curPos, pf);

			if ((daNote.wasGoodHit || (daNote.prevNote != null && daNote.prevNote.wasGoodHit)) && curPos >= 0 && daNote.isSustainNote)
				curPos = 0;

			// Detectar si la nota llegó al strum, está siendo tocada o presionada
			var isAtStrum = (Math.abs(curPos) <= hitWindow) || daNote.wasGoodHit || (curPos <= 0 && curPos >= -hitWindow * 2.5);
			if (!isAtStrum) continue;

			var noteDist = renderer.getNoteDist(i);
			noteDist = renderer.modifierTable.applyNoteDistMods(noteDist, lane, pf);

			var incomingAngle = renderer.modifierTable.applyIncomingAngleMods(lane, curPos, pf);
			if (noteDist < 0) incomingAngle[0] += 180;

			var origX = daNote.x;
			var origY = daNote.y;

			var timeFactor = (curPos <= 0 ? (-curPos / 100.0) : 0.0);

			for (c in 0...copyCount) {
				var step = (c + 1);
				NoteMovement.setNotePath(daNote, lane, daNote.speed, curPos, noteDist, incomingAngle[0], incomingAngle[1]);

				var copyData = renderer.createDataFromNote(i, pf, curPos, noteDist, incomingAngle, daNote);
				renderer.modifierTable.applyNoteMods(copyData, lane, curPos, pf);

				var totalOffX = offX * step * offsetMult;
				var totalOffY = baseOffsetY * step * offsetMult;
				var totalOffZ = offZ * step * offsetMult;

				if (speedVal != 0) {
					totalOffX += (offX != 0 ? (offX > 0 ? 1 : -1) : 0) * (timeFactor * speedVal * 25.0);
					totalOffY += (baseOffsetY != 0 ? (baseOffsetY > 0 ? 1 : -1) : -1) * (timeFactor * speedVal * 25.0);
				}

				copyData.x += totalOffX * currentValue;
				copyData.y += totalOffY * currentValue;
				copyData.z += totalOffZ * currentValue;

				var lifeFade = 1.0;
				if (timeFactor > 0 && speedVal > 0) {
					lifeFade = Math.max(0.0, 1.0 - (timeFactor * speedVal * fadeSpeedVal * 0.35));
					if (lifeFade <= 0.001) continue; // se desvanece por completo y se destruye
				}

				var fade = (copyCount > 1) ? (1.0 - (c / copyCount) * 0.5) : 1.0;
				copyData.alpha *= alphaVal * fade * lifeFade * currentValue;

				copyData.finalizeColorFill();
				extra.push(copyData);
			}

			daNote.x = origX;
			daNote.y = origY;
		}
		return extra;
	}
}

class StrumTrail {
	public var startBeat:Float;
	public var durationBeats:Float;
	public var easeName:String;
	public var startAlpha:Float;
	public var offX:Float;
	public var offY:Float;
	public var offZ:Float;
	public var scX:Float;
	public var scY:Float;
	public var angX:Float;
	public var angY:Float;
	public var angZ:Float;
	public var skX:Float;
	public var skY:Float;
	public var amount:Int;
	public var applyMods:Bool;
	public var forceStatic:Bool;

	public function new() {}
}

class CopyStrumModifier extends Modifier {
	public var activeTrails:Array<StrumTrail> = [];
	public var hasCalledEvent:Bool = false;

	override function setupSubValues() {
		subValues.set('x', new ModifierSubValue(0.0));
		subValues.set('y', new ModifierSubValue(0.0));
		subValues.set('z', new ModifierSubValue(0.0));
		subValues.set('alpha', new ModifierSubValue(1.0));
		subValues.set('amount', new ModifierSubValue(1.0));
		subValues.set('scale', new ModifierSubValue(1.0));
		subValues.set('scaleX', new ModifierSubValue(1.0));
		subValues.set('scaleY', new ModifierSubValue(1.0));
		subValues.set('angle', new ModifierSubValue(0.0));
		subValues.set('angleX', new ModifierSubValue(0.0));
		subValues.set('angleY', new ModifierSubValue(0.0));
		subValues.set('angleZ', new ModifierSubValue(0.0));
		subValues.set('skewX', new ModifierSubValue(0.0));
		subValues.set('skewY', new ModifierSubValue(0.0));
		subValues.set('forceStatic', new ModifierSubValue(1.0));
		subValues.set('applyMods', new ModifierSubValue(1.0));
	}

	function getSubVal(key:String, defaultVal:Float = 0.0):Float {
		if (subValues.exists(key))
			return subValues.get(key).value;
		return defaultVal;
	}

	override function reset() {
		super.reset();
		activeTrails = [];
		hasCalledEvent = false;
	}

	function createTrail(alphaVal:Float, time:Float, ease:String, beat:Float):StrumTrail {
		var trail = new StrumTrail();
		trail.startBeat = beat;

		var crochetSec = (Conductor.crochet > 0) ? (Conductor.crochet * 0.001) : 0.5;
		var durBeats = (time > 0) ? (time / crochetSec) : 1.0;
		trail.durationBeats = Math.max(0.01, durBeats);
		trail.easeName = (ease != null && ease != "") ? ease : "linear";

		var alphaSub = getSubVal('alpha', 1.0);
		trail.startAlpha = (alphaVal <= 0.0001) ? alphaSub : (alphaVal * alphaSub);

		trail.offX = 0.0;
		trail.offY = 0.0;
		trail.offZ = 0.0;

		var sc = getSubVal('scale', 1.0);
		trail.scX = getSubVal('scaleX', 1.0) * sc;
		trail.scY = getSubVal('scaleY', 1.0) * sc;

		var ang = getSubVal('angle', 0.0);
		trail.angX = getSubVal('angleX', 0.0);
		trail.angY = getSubVal('angleY', 0.0);
		trail.angZ = getSubVal('angleZ', 0.0) + ang;

		trail.skX = getSubVal('skewX', 0.0);
		trail.skY = getSubVal('skewY', 0.0);

		var amountVal = getSubVal('amount', 1.0);
		trail.amount = Std.int(Math.max(amountVal, 1));

		trail.forceStatic = getSubVal('forceStatic', 1.0) > 0.5;
		trail.applyMods = getSubVal('applyMods', 1.0) > 0.5;

		return trail;
	}

	override function onEvent(val:Float, time:Float, ease:String, beat:Float):Void {
		hasCalledEvent = true;

		if (activeTrails.length > 0 && Math.abs(activeTrails[activeTrails.length - 1].startBeat - beat) < 0.001) {
			var existing = activeTrails[activeTrails.length - 1];
			var alphaSub = getSubVal('alpha', 1.0);
			if (val > 0.0001) existing.startAlpha = val * alphaSub;
			return;
		}

		var trail = createTrail(val, time, ease, beat);
		activeTrails.push(trail);
	}

	override function onSubModEvent(subMod:String, val:Float, time:Float, ease:String, beat:Float):Void {
		hasCalledEvent = true;

		var trail:StrumTrail = null;
		if (activeTrails.length > 0 && Math.abs(activeTrails[activeTrails.length - 1].startBeat - beat) < 0.001) {
			trail = activeTrails[activeTrails.length - 1];
		} else {
			trail = createTrail(1.0, time, ease, beat);
			activeTrails.push(trail);
		}

		switch (subMod) {
			case 'x', 'xoffset', 'offsetX':
				trail.offX = val;
			case 'y', 'yoffset', 'offsetY':
				trail.offY = val;
			case 'z', 'zoffset', 'offsetZ':
				trail.offZ = val;
			case 'alpha':
				trail.startAlpha = val;
			case 'scale':
				trail.scX = val;
				trail.scY = val;
			case 'scaleX':
				trail.scX = val;
			case 'scaleY':
				trail.scY = val;
			case 'angle':
				trail.angZ = val;
			case 'angleX':
				trail.angX = val;
			case 'angleY':
				trail.angY = val;
			case 'angleZ':
				trail.angZ = val;
			case 'skewX':
				trail.skX = val;
			case 'skewY':
				trail.skY = val;
		}
	}

	override function hasExtraStrumData():Bool {
		return !hasCalledEvent || activeTrails.length > 0;
	}

	override function gatherExtraStrumData(pf:Int):Array<NotePositionData> {
		if (renderer == null) return null;

		var strumCount = renderer.strumGroup.members.length;
		var extra:Array<NotePositionData> = [];

		if (!hasCalledEvent) {
			var alphaSub = getSubVal('alpha', 1.0);
			if (alphaSub <= 0.001) return null;

			var amountVal = getSubVal('amount', 1.0);
			var copyCount = Std.int(Math.max(amountVal, 1));

			var offX = getSubVal('x', 0.0);
			var offY = getSubVal('y', 0.0);
			var offZ = getSubVal('z', 0.0);

			var sc = getSubVal('scale', 1.0);
			var scX = getSubVal('scaleX', 1.0) * sc;
			var scY = getSubVal('scaleY', 1.0) * sc;

			var ang = getSubVal('angle', 0.0);
			var angX = getSubVal('angleX', 0.0);
			var angY = getSubVal('angleY', 0.0);
			var angZ = getSubVal('angleZ', 0.0) + ang;

			var skX = getSubVal('skewX', 0.0);
			var skY = getSubVal('skewY', 0.0);

			var forceStaticVal = getSubVal('forceStatic', 1.0) > 0.5;
			var applyModsVal = getSubVal('applyMods', 1.0) > 0.5;

			for (lane in 0...strumCount) {
				if (!checkLane(lane) || !checkPlayField(pf)) continue;

				for (c in 0...copyCount) {
					var step = c + 1;
					var defX = NoteMovement.defaultStrumX.length > lane ? NoteMovement.defaultStrumX[lane] : 0.0;
					var defY = NoteMovement.defaultStrumY.length > lane ? NoteMovement.defaultStrumY[lane] : 0.0;
					var defScale = NoteMovement.defaultScale.length > lane ? NoteMovement.defaultScale[lane] : 0.7;
					var defSkewX = NoteMovement.defaultSkewX.length > lane ? NoteMovement.defaultSkewX[lane] : 0.0;
					var defSkewY = NoteMovement.defaultSkewY.length > lane ? NoteMovement.defaultSkewY[lane] : 0.0;

					var copyData = NotePositionData.get();
					copyData.setupStrum(defX, defY, 0, lane, defScale, defScale, defSkewX, defSkewY, pf);

					if (pf < renderer.playfields.length)
						renderer.playfields[pf].applyOffsets(copyData);

					if (applyModsVal)
						renderer.modifierTable.applyStrumMods(copyData, lane, pf);

					copyData.x += offX * step;
					copyData.y += offY * step;
					copyData.z += offZ * step;

					copyData.scaleX = defScale * scX;
					copyData.scaleY = defScale * scY;

					copyData.angleX += angX;
					copyData.angleY += angY;
					copyData.angleZ += angZ;

					copyData.skewX += skX;
					copyData.skewY += skY;

					var copyFade = (copyCount > 1) ? (1.0 - (c / copyCount) * 0.4) : 1.0;
					copyData.alpha = Math.max(0.0, Math.min(1.0, alphaSub * copyFade));
					copyData.forceStatic = forceStaticVal;

					copyData.finalizeColorFill();
					extra.push(copyData);
				}
			}
			return extra;
		}

		var curBeat = Modifier.beat;
		var i = activeTrails.length - 1;
		while (i >= 0) {
			var trail = activeTrails[i];
			var elapsedBeats = curBeat - trail.startBeat;
			var progress = elapsedBeats / trail.durationBeats;

			if (progress >= 1.0) {
				activeTrails.splice(i, 1);
				i--;
				continue;
			}

			if (progress < 0) {
				i--;
				continue;
			}

			var easeFunc = ModchartUtil.getFlxEaseByString(trail.easeName);
			var eased = easeFunc(Math.max(0.0, Math.min(1.0, progress)));
			var curAlpha = trail.startAlpha * (1.0 - eased);

			if (curAlpha <= 0.001) {
				activeTrails.splice(i, 1);
				i--;
				continue;
			}

			var copyCount = trail.amount;

			for (lane in 0...strumCount) {
				if (!checkLane(lane) || !checkPlayField(pf)) continue;

				for (c in 0...copyCount) {
					var step = c + 1;
					var defX = NoteMovement.defaultStrumX.length > lane ? NoteMovement.defaultStrumX[lane] : 0.0;
					var defY = NoteMovement.defaultStrumY.length > lane ? NoteMovement.defaultStrumY[lane] : 0.0;
					var defScale = NoteMovement.defaultScale.length > lane ? NoteMovement.defaultScale[lane] : 0.7;
					var defSkewX = NoteMovement.defaultSkewX.length > lane ? NoteMovement.defaultSkewX[lane] : 0.0;
					var defSkewY = NoteMovement.defaultSkewY.length > lane ? NoteMovement.defaultSkewY[lane] : 0.0;

					var copyData = NotePositionData.get();
					copyData.setupStrum(defX, defY, 0, lane, defScale, defScale, defSkewX, defSkewY, pf);

					if (pf < renderer.playfields.length)
						renderer.playfields[pf].applyOffsets(copyData);

					if (trail.applyMods)
						renderer.modifierTable.applyStrumMods(copyData, lane, pf);

					var curOffX = trail.offX * step * eased;
					var curOffY = trail.offY * step * eased;
					var curOffZ = trail.offZ * step * eased;

					copyData.x += curOffX;
					copyData.y += curOffY;
					copyData.z += curOffZ;

					copyData.scaleX = defScale * trail.scX;
					copyData.scaleY = defScale * trail.scY;

					copyData.angleX += trail.angX * eased;
					copyData.angleY += trail.angY * eased;
					copyData.angleZ += trail.angZ * eased;

					copyData.skewX += trail.skX * eased;
					copyData.skewY += trail.skY * eased;

					var copyFade = (copyCount > 1) ? (1.0 - (c / copyCount) * 0.4) : 1.0;
					copyData.alpha = Math.max(0.0, Math.min(1.0, curAlpha * copyFade));
					copyData.forceStatic = trail.forceStatic;

					copyData.finalizeColorFill();
					extra.push(copyData);
				}
			}
			i--;
		}

		return extra;
	}
}

class WormModifier extends Modifier {
	override function setupSubValues() {
		subValues.set('spacing', new ModifierSubValue(230.0));
		subValues.set('count', new ModifierSubValue(20.0));
		subValues.set('speed', new ModifierSubValue(1.0));
	}

	function getRowLayout():{rowWidth:Float, fullRows:Int, remaining:Int, perRow:Int} {
		var ghostCount = Std.int(Math.max(subValues.get('count').value, 1));
		var spacing = subValues.get('spacing').value;
		var perRow = NoteMovement.totalKeyCount;
		var minX = NoteMovement.defaultStrumX[0];
		var maxX = NoteMovement.defaultStrumX[0];
		for (lane in 0...perRow) {
			var lx = NoteMovement.defaultStrumX[lane];
			if (lx < minX) minX = lx;
			if (lx > maxX) maxX = lx;
		}
		return {
			rowWidth: maxX + spacing - minX,
			fullRows: Std.int(ghostCount / perRow),
			remaining: ghostCount % perRow,
			perRow: perRow
		};
	}

	override function gatherExtraStrumData(pf:Int):Array<NotePositionData> {
		if (currentValue == baseValue || renderer == null) return null;

		var layout = getRowLayout();
		var scroll = Conductor.songPosition * 0.001 * (subValues.get('speed').value * states.PlayState.songMultiplier);
		var extra:Array<NotePositionData> = [];

		for (row in 0...layout.fullRows) {
			var rowOffset = layout.rowWidth * (row + 1) + scroll;
			for (lane in 0...layout.perRow) {
				if (!checkLane(lane) || !checkPlayField(pf)) continue;
				extra.push(makeRowStrum(lane, pf, rowOffset));
			}
		}
		if (layout.remaining > 0) {
			var rowOffset = layout.rowWidth * (layout.fullRows + 1) + scroll;
			for (lane in 0...layout.remaining) {
				if (!checkLane(lane) || !checkPlayField(pf)) continue;
				extra.push(makeRowStrum(lane, pf, rowOffset));
			}
		}
		return extra;
	}

	function makeRowStrum(lane:Int, pf:Int, offset:Float):NotePositionData {
		var scale = NoteMovement.defaultScale.length > lane ? NoteMovement.defaultScale[lane] : 0.7;
		var skewX = NoteMovement.defaultSkewX.length > lane ? NoteMovement.defaultSkewX[lane] : 0;
		var skewY = NoteMovement.defaultSkewY.length > lane ? NoteMovement.defaultSkewY[lane] : 0;
		var strumData = NotePositionData.get();
		strumData.setupStrum(NoteMovement.defaultStrumX[lane], NoteMovement.defaultStrumY[lane], 0, lane, scale, scale, skewX, skewY, pf);
		if (pf < renderer.playfields.length)
			renderer.playfields[pf].applyOffsets(strumData);
		renderer.modifierTable.applyStrumMods(strumData, lane, pf);
		strumData.x += offset;
		return strumData;
	}

	override function gatherExtraNoteData(pf:Int):Array<NotePositionData> {
		if (currentValue == baseValue || renderer == null) return null;

		var layout = getRowLayout();
		var scroll = Conductor.songPosition * 0.001 * (subValues.get('speed').value * states.PlayState.songMultiplier);

		var extra:Array<NotePositionData> = [];
		var maxDist = 2000.0;

		for (i in 0...renderer.notes.members.length) {
			var daNote = renderer.notes.members[i];
			if (daNote == null) continue;
			var lane = renderer.getLane(i);
			if (!checkLane(lane) || !checkPlayField(pf)) continue;

			var curPos = renderer.getNoteCurPos(i);
			curPos = renderer.modifierTable.applyCurPosMods(lane, curPos, pf);

			if ((daNote.wasGoodHit || (daNote.prevNote != null && daNote.prevNote.wasGoodHit)) && curPos >= 0 && daNote.isSustainNote)
				curPos = 0;

			if (Math.abs(curPos) > maxDist) continue;

			var noteDist = renderer.getNoteDist(i);
			noteDist = renderer.modifierTable.applyNoteDistMods(noteDist, lane, pf);

			var incomingAngle = renderer.modifierTable.applyIncomingAngleMods(lane, curPos, pf);
			if (noteDist < 0) incomingAngle[0] += 180;

			for (row in 0...layout.fullRows) {
				extra.push(makeRowNote(i, pf, curPos, noteDist, incomingAngle, layout.rowWidth * (row + 1) + scroll, daNote));
			}
			if (layout.remaining > 0 && lane < layout.remaining) {
				extra.push(makeRowNote(i, pf, curPos, noteDist, incomingAngle, layout.rowWidth * (layout.fullRows + 1) + scroll, daNote));
			}
		}
		return extra;
	}

	function makeRowNote(noteIndex:Int, pf:Int, curPos:Float, noteDist:Float, incomingAngle:Array<Float>, offset:Float, ?daNote:Note = null):NotePositionData {
		var noteData = renderer.createDataFromNote(noteIndex, pf, curPos, noteDist, incomingAngle, daNote);
		renderer.modifierTable.applyNoteMods(noteData, renderer.getLane(noteIndex), curPos, pf);
		noteData.x += offset;
		return noteData;
	}
}

class CameraModifier extends Modifier {
    override function setupSubValues() {
        subValues.set('camera', new ModifierSubValue(0.0));
        subValues.set('scrollX', new ModifierSubValue(0.0));
        subValues.set('scrollY', new ModifierSubValue(0.0));
        subValues.set('zoom', new ModifierSubValue(0.0));
        subValues.set('layer', new ModifierSubValue(0.0));
    }

    // If set to any non-empty id (name, .id or curCharacter), the renderer is
    // placed behind THAT object wherever it lives (stage bg, characters,
    // camGame or camHUD stuff, nested groups, lua sprites...). Wins over the
    // numeric `layer` subvalue below.
    public var layerId:String = null;

    var lastAppliedLayer:Int = 0;

    override public function getNotePath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
        var camVal = subValues.get('camera') != null ? subValues.get('camera').value : 0.0;
        var layVal = subValues.get('layer') != null ? subValues.get('layer').value : 0.0;
        var layName = subValues.get('layer') != null ? subValues.get('layer').name : '';
        var zVal = subValues.get('zoom') != null ? subValues.get('zoom').value : 0.0;
        var sxVal = subValues.get('scrollX') != null ? subValues.get('scrollX').value : 0.0;
        var syVal = subValues.get('scrollY') != null ? subValues.get('scrollY').value : 0.0;
        if (currentValue != baseValue || camVal != 0 || layVal != 0 || (layName != null && layName != '') || zVal != 0 || sxVal != 0 || syVal != 0) {
            noteMath(noteData, lane, curPos, pf);
        }
    }

    override public function getStrumPath(noteData:NotePositionData, lane:Int, pf:Int) {
        var camVal = subValues.get('camera') != null ? subValues.get('camera').value : 0.0;
        var layVal = subValues.get('layer') != null ? subValues.get('layer').value : 0.0;
        var layName = subValues.get('layer') != null ? subValues.get('layer').name : '';
        var zVal = subValues.get('zoom') != null ? subValues.get('zoom').value : 0.0;
        var sxVal = subValues.get('scrollX') != null ? subValues.get('scrollX').value : 0.0;
        var syVal = subValues.get('scrollY') != null ? subValues.get('scrollY').value : 0.0;
        if (currentValue != baseValue || camVal != 0 || layVal != 0 || (layName != null && layName != '') || zVal != 0 || sxVal != 0 || syVal != 0) {
            strumMath(noteData, lane, pf);
        }
    }

    override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
        var camValue = subValues.get('camera').value;
        var lay:Int = Std.int(subValues.get('layer').value);
        var layName:String = subValues.get('layer').name;
        var layWants:Bool = lay > 0 || (layName != null && layName != '');
        var zVal = subValues.get('zoom').value;
        var sxVal = subValues.get('scrollX').value;
        var syVal = subValues.get('scrollY').value;

        // forced-active: many charts only tween/set subvalues (e.g. camera:camera,
        // camera:layer) without ever turning the modifier itself on, so any active
        // subvalue enables it just the same as currentValue >= 0.5.
        var active:Bool = currentValue >= 0.5 || camValue != 0 || layWants || zVal != 0 || sxVal != 0 || syVal != 0;
        if (!active) {
            if (lastAppliedLayer != 0)
                restoreRenderer();
            return;
        }

        var useId:Bool = (layerId != null && layerId != '') || (layName != null && layName != '');
        var wantsLayer:Bool = layWants || useId;

        var targetCamName:String = "camGame";
        var roundedCam:Int = Math.round(camValue);
        if (roundedCam == 2) {
            targetCamName = "camOther";
        } else if (roundedCam == 0 && !wantsLayer && currentValue < 0.5) {
            targetCamName = "camHUD";
        } else {
            targetCamName = "camGame";
        }

        if (renderer != null && renderer.inEditor) {
            var editor:Dynamic = renderer.instance;
            if (targetCamName == "camHUD")
                noteData.camera = editor.camGame;
            else if (targetCamName == "camOther")
                noteData.camera = editor.camHUD;
            else
                noteData.camera = editor.camGamePreview;
        } else if (PlayState.instance != null) {
            if (targetCamName == "camGame") {
                noteData.camera = PlayState.instance.camGame;
            } else if (targetCamName == "camOther") {
                noteData.camera = PlayState.instance.camOther != null ? PlayState.instance.camOther : PlayState.instance.camHUD;
            } else {
                noteData.camera = PlayState.instance.camHUD;
            }

            if (wantsLayer) {
                var layoutKey = useId ? -1 : lay;
                if (lastAppliedLayer != layoutKey)
                    placeRendererBehind(lay, layoutKey);
            } else if (targetCamName == "camGame") {
                if (lastAppliedLayer != -999)
                    placeRendererBehind(4, -999);
            } else if (lastAppliedLayer != 0) {
                restoreRenderer();
            }
        }
        noteData.cameraScrollX = sxVal;
        noteData.cameraScrollY = syVal;
        noteData.cameraZoom = zVal;
    }

    override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
        noteMath(noteData, lane, 0, pf);
    }

    // Puts the renderer just before an arbitrary object, wherever it lives
    // (a nested group, the stage, characters, camHUD stuff, etc).
    // Resolution order: layerId field -> "layer" subvalue name -> numeric quick-layers:
    // 1=gf, 2=boyfriend, 3=dad, 4=stage (behind every background),
    // 5=foreground sprites, 6=infrontOfGF sprites.
    function placeRendererBehind(layer:Int, layoutKey:Int) {
        if (renderer == null || renderer.inEditor) return;
        var state = PlayState.instance;
        if (state == null) return;

        var target:Dynamic = null;
        #if LEATHER
        var layName:String = subValues.get('layer').name;
        if (layerId != null && layerId != '') {
            target = findById(state, layerId);
            if (target == null)
                target = resolveLeatherId(state, layerId);
        } else if (layName != null && layName != '') {
            target = findById(state, layName);
            if (target == null)
                target = resolveLeatherId(state, layName);
        } else switch (layer) {
            case 1:
                target = PlayState.gf;
            case 2:
                target = PlayState.boyfriend;
            case 3:
                target = PlayState.dad;
            case 4:
                target = state.stage;
            case 5:
                target = state.stage.foregroundSprites;
            case 6:
                target = state.stage.infrontOfGFSprites;
            default:
                target = state.stage;
        }
        #end
        if (target == null) {
            var r:FlxObject = renderer;
            var parent = findParent(state, r);
            if (parent != null)
                parent.remove(r);
            state.insert(0, r);
            lastAppliedLayer = layoutKey;
            return;
        }

        var actualTarget:Dynamic = target;
        #if LEATHER
        if (Std.isOfType(target, game.Character)) {
            var c:game.Character = cast target;
            if (c.otherCharacters != null && c.otherCharacters.length > 0)
                actualTarget = c.otherCharacters[0];
        }
        #end

        var parent = findParent(state, actualTarget);
        if (parent == null) {
            trace('[CameraModifier] placeRendererBehind FAILED: parent group for target not found');
            return;
        }
        var targetIndex:Int = (cast parent.members:Array<Dynamic>).indexOf(actualTarget);
        if (targetIndex < 0) {
            trace('[CameraModifier] placeRendererBehind FAILED: targetIndex < 0');
            return;
        }

        var r:FlxObject = renderer;
        var rendererParent = findParent(state, r);
        if (rendererParent == parent && (cast parent.members:Array<Dynamic>).indexOf(r) == targetIndex) {
            lastAppliedLayer = layoutKey;
            return;
        }
        if (rendererParent != null)
            rendererParent.remove(r);
        parent.insert(targetIndex, r);
        lastAppliedLayer = layoutKey;
        trace('[CameraModifier] placeRendererBehind SUCCESS: placed renderer behind targetIndex=${targetIndex} of parent');
    }

    function restoreRenderer() {
        if (renderer == null || renderer.inEditor) return;
        var state = PlayState.instance;
        if (state == null) return;
        trace('[CameraModifier] restoreRenderer called: moving renderer back to state');

        var r:FlxObject = renderer;
        var parent = findParent(state, r);
        if (parent != null)
            parent.remove(r);
        state.add(r);
        lastAppliedLayer = 0;
    }

    // Deep search: returns the group that DIRECTLY contains target.
    function findParent(group:Dynamic, target:Dynamic):Dynamic {
        if (group == null) return null;
        var members:Array<Dynamic> = cast group.members;
        if (members == null) return null;
        if (members.indexOf(target) >= 0) return group;
        for (m in members) {
            if (m == null) continue;
            if (isGroup(m)) {
                var p = findParent(m, target);
                if (p != null) return p;
            }
        }
        return null;
    }

    // Deep search by name/id/curCharacter; returns the object itself.
    function findById(group:Dynamic, id:String):Dynamic {
        if (group == null) return null;
        var members:Array<Dynamic> = cast group.members;
        if (members == null) return null;
        for (m in members) {
            if (m == null) continue;
            if (Reflect.field(m, "name") == id) return m;
            if (Reflect.hasField(m, "curCharacter") && Std.string(Reflect.field(m, "curCharacter")) == id) return m;
            if (Reflect.hasField(m, "id") && Std.string(Reflect.field(m, "id")) == id) return m;
            if (isGroup(m)) {
                var r = findById(m, id);
                if (r != null) return r;
            }
        }
        return null;
    }

    // Duck-type check: anything exposing a members Array acts as a group.
    function isGroup(o:Dynamic):Bool {
        return o != null && Reflect.hasField(o, "members") && Std.isOfType(Reflect.field(o, "members"), Array);
    }

    #if LEATHER
    // Extra id lookup for things that don't carry a matching .name in the
    // members tree: lua sprites (makeStageSprite/makeLuaSprite), PlayState
    // instance/static fields (gf, boyfriend, dad, stage, healthBar...), and
    // stage props. Mirrors the engine's own getActorByName().
    function resolveLeatherId(state:PlayState, id:String):Dynamic {
        var spr:Dynamic = LuaScript.lua_Sprites.get(id);
        if (spr != null && (Std.isOfType(spr, FlxObject) || isGroup(spr))) return spr;

        var prop:Dynamic = Reflect.getProperty(state, id);
        if (prop == null) prop = Reflect.getProperty(PlayState, id);
        if (prop != null && (Std.isOfType(prop, FlxObject) || isGroup(prop))) return prop;

        if (state.stage != null) {
            var stageProp:Dynamic = Reflect.getProperty(state.stage, id);
            if (stageProp != null && (Std.isOfType(stageProp, FlxObject) || isGroup(stageProp))) return stageProp;
        }
        return null;
    }
    #end
}


class InfiniteFormModifier extends Modifier {
	override function setupSubValues() {
		subValues.set("speed", new ModifierSubValue(1.0));
		subValues.set("amplitude", new ModifierSubValue(600.0));
		subValues.set("phase", new ModifierSubValue(0.0));
	}

	function getCenterX():Float {
		var totalX:Float = 0;
		for (x in NoteMovement.defaultStrumX)
			totalX += x;
		return totalX / NoteMovement.defaultStrumX.length;
	}

	function getCenterY():Float {
		return flixel.FlxG.height / 2 - 56;
	}

	function infinityMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int, isStrum:Bool = false) {
		var mult = states.PlayState.songMultiplier;
		if (mult == 0) mult = 1.0;
		var speed = subValues.get("speed").value * mult;
		var amp = subValues.get("amplitude").value;
		var phase = subValues.get("phase").value * Math.PI / 4;

		var safeAmp = amp;
		if (safeAmp == 0) safeAmp = 1.0;
		
		// To prevent desync/visual acceleration at massive amplitudes, we MUST decouple physical speed from amplitude.
		// A constant of 0.75 is a good middle ground: it's playable, doesn't cause desync, and traces a good amount of the curve.
		var dynamicMult = 0.75 / Math.abs(safeAmp);

		var centerX = getCenterX();
		var centerY = getCenterY();

		if (isStrum) {
			noteData.x += (centerX - noteData.x) * currentValue;
			noteData.y += (centerY - noteData.y) * currentValue;
		}

		if (!isStrum) {
			var t = (curPos * dynamicMult * speed) + phase + (Math.PI / 2);
			var infX = amp * Math.cos(t);
			var infY = (amp * Math.sin(2.0 * t)) / 2.0;

			var targetX = centerX + infX;
			var targetY = centerY + infY;

			noteData.x += (targetX - noteData.x) * currentValue;
			noteData.y += (targetY - noteData.y) * currentValue;
		}
	}

	override function noteMath(noteData:NotePositionData, lane:Int, curPos:Float, pf:Int) {
		infinityMath(noteData, lane, curPos, pf, false);
	}

	override function strumMath(noteData:NotePositionData, lane:Int, pf:Int) {
		infinityMath(noteData, lane, 0, pf, true);
	}
}
