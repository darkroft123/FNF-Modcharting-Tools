package modcharting;

import openfl.geom.Vector3D;
import flixel.FlxG;
#if LEATHER
import game.Note;
import game.Conductor;
#elseif (PSYCH && PSYCHVERSION >= "0.7")
import objects.Note;
#else
import Note;
#end

using StringTools;

class SustainRenderer {
	static var _vec3:Vector3D = new Vector3D();
	static var _vec3b:Vector3D = new Vector3D();

	public static inline function getNoteSustainDuration(daNote:Note):Float {
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
		#if LEATHER
		return Conductor.getStepDurationAt(daNote.strumTime);
		#else
		return ModchartUtil.getFakeCrochetAt(daNote.strumTime) / 4;
		#end
	}

	public static inline function sustainScaleMultiplier(daNote:Note, lane:Int):Float {
		if (daNote.inEditor)
			return getNoteSustainDuration(daNote) / 100 * Note.SCALE_MULT * daNote.speed;
		var baseScale:Float = NoteMovement.defaultScale.length > lane ? NoteMovement.defaultScale[lane] : 0.7;
		var target:Float = daNote.sustainScaleY;
		if (target <= 0)
			return 1;
		return target / baseScale;
	}

	public static function drawSustainAsSprite(renderer:PlayfieldRenderer, noteData:NotePositionData):Void {
		var daNote = renderer.notes.members[noteData.index];
		var changeX:Bool = noteData.z != 0;
		var animName = (daNote.animation.curAnim != null) ? daNote.animation.curAnim.name : "";
		var isHoldEnd = animName.endsWith("end");

		var thisNotePos:Vector3D;
		if (changeX) {
			_vec3.setTo(
				noteData.x + (daNote.width / 2) + ModchartUtil.getNoteOffsetX(daNote, renderer.instance),
				noteData.y + (daNote.height / 2),
				noteData.z * 0.001
			);
			thisNotePos = ModchartUtil.calculatePerspective(
				_vec3,
				ModchartUtil.defaultFOV * (Math.PI / 180),
				-(daNote.width / 2),
				-(daNote.height / 2)
			);
		} else {
			_vec3.setTo(noteData.x + ModchartUtil.getNoteOffsetX(daNote, renderer.instance), noteData.y, 0);
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

		renderer.addDataToNote(noteData, daNote);
		daNote.scrollFactor.set(noteData.cameraScrollX, noteData.cameraScrollY);
		daNote.cameras = (noteData.camera != null) ? [noteData.camera] : renderer.cameras;

		var oldX = daNote.x;
		var oldY = daNote.y;
		var oldScaleX = daNote.scale.x;
		var oldScaleY = daNote.scale.y;

		ModchartUtil.applyCameraZoomToSprite(daNote, noteData.camera, noteData.cameraZoom);

		var tempMesh = daNote.mesh;
		var savedNoteShader = daNote.shader;
		var savedOffsetX = daNote.offset.x;
		var savedOffsetY = daNote.offset.y;
		daNote.mesh = null;
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

	public static function drawSustainNote(renderer:PlayfieldRenderer, noteData:NotePositionData):Void {
		if (noteData.alpha <= 0.001 || !renderer.visible || renderer.alpha <= 0.001)
			return;

		if (utilities.Options.getData("optimizedModcharts")) {
			drawSustainAsSprite(renderer, noteData);
			return;
		}

		var daNote = renderer.notes.members[noteData.index];
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
			drawSustainAsSprite(renderer, noteData);
			return;
		}

		daNote.scrollFactor.set(0, 0);
		daNote.mesh.scrollFactor.x = daNote.scrollFactor.x;
		daNote.mesh.scrollFactor.y = daNote.scrollFactor.y;
		daNote.mesh.setColorTransform(
			noteData.redMultiplier,
			noteData.greenMultiplier,
			noteData.blueMultiplier,
			noteData.alpha,
			noteData.redOffset,
			noteData.greenOffset,
			noteData.blueOffset
		);

		var lane = noteData.lane;
		var yOffsetThingy = (NoteMovement.arrowSizes[lane] / 2);

		_vec3.setTo(
			noteData.x + (daNote.width / 2) + ModchartUtil.getNoteOffsetX(daNote, renderer.instance),
			noteData.y + (NoteMovement.arrowSizes[noteData.lane] / 2),
			noteData.z * 0.001
		);
		var thisNotePos = ModchartUtil.calculatePerspective(
			_vec3,
			ModchartUtil.defaultFOV * (Math.PI / 180),
			-(daNote.width / 2),
			yOffsetThingy - (NoteMovement.arrowSizes[noteData.lane] / 2)
		);

		var animName = (daNote.animation.curAnim != null) ? daNote.animation.curAnim.name : "";
		var isHoldEnd = animName.endsWith("end");

		var stepDuration = getNoteSustainDuration(daNote);
		var timeToNextSustain = stepDuration;

		if (isHoldEnd) {
			var baseScale:Float = NoteMovement.defaultScale.length > lane ? NoteMovement.defaultScale[lane] : 0.7;
			var capHeight:Float = daNote.frameHeight * baseScale;
			var speedFactor:Float = daNote.speed * 0.45;
			var capDuration:Float = (speedFactor > 0.001) ? (capHeight / speedFactor) : stepDuration;
			if (capDuration < stepDuration)
				timeToNextSustain = capDuration;
		}

		var timeOffsetEnd:Float = isHoldEnd ? -timeToNextSustain : -(timeToNextSustain + 1.5);
		var nextHalfNotePos:NotePositionData = getSustainPoint(renderer, noteData, -timeToNextSustain * 0.5);
		var nextNotePos:NotePositionData = getSustainPoint(renderer, noteData, timeOffsetEnd);

		var flipGraphic = (noteData.noteDist > 0);
		var fixedAngY = ((noteData.incomingAngleY % 360) + 360) % 360;
		var reverseClip = (fixedAngY > 90 && fixedAngY < 270);

		try {
			var savedMeshShader = daNote.mesh.shader;
			daNote.mesh.shader = noteData.hasColorFill ? null : daNote.shader;
			daNote.mesh.constructVertices(noteData, thisNotePos, nextHalfNotePos, nextNotePos, flipGraphic, reverseClip);
			daNote.mesh.scrollFactor.set(noteData.cameraScrollX, noteData.cameraScrollY);
			daNote.mesh.cameras = (noteData.camera != null) ? [noteData.camera] : renderer.cameras;

			ModchartUtil.applyCameraZoomToMesh(daNote.mesh, noteData.camera, noteData.cameraZoom);

			daNote.mesh.draw();
		} catch (e:Dynamic) {
			drawSustainAsSprite(renderer, noteData);
		}

		NotePositionData.recycle(nextHalfNotePos);
		NotePositionData.recycle(nextNotePos);
	}

	public static function getSustainPoint(renderer:PlayfieldRenderer, noteData:NotePositionData, timeOffset:Float):NotePositionData {
		var daNote = renderer.notes.members[noteData.index];
		var songSpeed = daNote.speed;
		var lane = noteData.lane;
		var pf = noteData.playfieldIndex;

		var noteDist = renderer.getNoteDist(noteData.index);
		var curPos = renderer.getNoteCurPos(noteData.index, timeOffset);

		curPos = renderer.modifierTable.applyCurPosMods(lane, curPos, pf);
		if ((daNote.wasGoodHit || (daNote.prevNote != null && daNote.prevNote.wasGoodHit)) && curPos >= 0)
			curPos = 0;
		noteDist = renderer.modifierTable.applyNoteDistMods(noteDist, lane, pf);
		var incomingAngle = renderer.modifierTable.applyIncomingAngleMods(lane, curPos, pf);
		if (noteDist < 0) incomingAngle[0] += 180;

		NoteMovement.setNotePath(daNote, lane, songSpeed, curPos, noteDist, incomingAngle[0], incomingAngle[1]);
		var result = renderer.createDataFromNote(noteData.index, pf, curPos, noteDist, incomingAngle, daNote);
		renderer.modifierTable.applyNoteMods(result, lane, curPos, pf);
		result.finalizeColorFill();

		var arrowSize = NoteMovement.arrowSizes[lane] / 2;
		_vec3b.setTo(
			result.x + (daNote.width / 2) + ModchartUtil.getNoteOffsetX(daNote, renderer.instance),
			result.y + (NoteMovement.arrowSizes[result.lane] / 2),
			result.z * 0.001
		);
		var finalPos = ModchartUtil.calculatePerspective(
			_vec3b,
			ModchartUtil.defaultFOV * (Math.PI / 180),
			-(daNote.width / 2),
			0
		);
		result.x = finalPos.x;
		result.y = finalPos.y;
		result.z = finalPos.z;
		return result;
	}
}
