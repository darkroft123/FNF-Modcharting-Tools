package modcharting;

import openfl.geom.Vector3D;
import flixel.FlxSprite;
import modcharting.PlayfieldRenderer.StrumNoteType;
#if LEATHER
import game.Note;
#elseif (PSYCH && PSYCHVERSION >= "0.7")
import objects.Note;
#else
import Note;
#end

using StringTools;

class NoteRenderer {
	static var _vec3:Vector3D = new Vector3D();
	static var _vec3b:Vector3D = new Vector3D();

	public static function addDataToStrum(strumData:NotePositionData, strum:StrumNoteType):Void {
		strum.x = strumData.x;
		strum.y = strumData.y;
		strum.angle3D.x = strumData.angleX;
		strum.angle3D.y = strumData.angleY;
		strum.angle3D.z = strumData.angleZ;
		strum.scale.x = strumData.scaleX;
		strum.scale.y = strumData.scaleY;
		strum.skew.x = strumData.skewX;
		strum.skew.y = strumData.skewY;
		strum.setColorTransform(
			strumData.redMultiplier,
			strumData.greenMultiplier,
			strumData.blueMultiplier,
			strumData.alpha,
			strumData.redOffset,
			strumData.greenOffset,
			strumData.blueOffset
		);
	}

	public static function addDataToNote(noteData:NotePositionData, daNote:Note):Void {
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
		daNote.setColorTransform(
			noteData.redMultiplier,
			noteData.greenMultiplier,
			noteData.blueMultiplier,
			noteData.alpha,
			noteData.redOffset,
			noteData.greenOffset,
			noteData.blueOffset
		);
	}

	public static function drawStrum(renderer:PlayfieldRenderer, noteData:NotePositionData):Void {
		if (noteData.alpha <= 0)
			return;

		var changeX:Bool = noteData.z != 0;
		var strumNote = renderer.strumGroup.members[noteData.index];
		var thisNotePos:Vector3D;

		if (changeX) {
			_vec3b.setTo(noteData.x + (strumNote.width / 2), noteData.y + (strumNote.height / 2), noteData.z * 0.001);
			thisNotePos = ModchartUtil.calculatePerspective(
				_vec3b,
				ModchartUtil.defaultFOV * (Math.PI / 180),
				-(strumNote.width / 2),
				-(strumNote.height / 2)
			);
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
		strumNote.cameras = (noteData.camera != null) ? [noteData.camera] : renderer.cameras;

		var oldX = strumNote.x;
		var oldY = strumNote.y;
		var oldScaleX = strumNote.scale.x;
		var oldScaleY = strumNote.scale.y;

		ModchartUtil.applyCameraZoomToSprite(strumNote, noteData.camera, noteData.cameraZoom);

		strumNote.draw();

		strumNote.x = oldX;
		strumNote.y = oldY;
		strumNote.scale.x = oldScaleX;
		strumNote.scale.y = oldScaleY;
	}

	public static function drawNote(renderer:PlayfieldRenderer, noteData:NotePositionData):Void {
		if (noteData.alpha <= 0.001 || !renderer.visible || renderer.alpha <= 0.001)
			return;

		var changeX:Bool = noteData.z != 0;
		var daNote = renderer.notes.members[noteData.index];
		var thisNotePos:Vector3D;

		if (changeX) {
			_vec3b.setTo(
				noteData.x + (daNote.width / 2) + ModchartUtil.getNoteOffsetX(daNote, renderer.instance),
				noteData.y + (daNote.height / 2),
				noteData.z * 0.001
			);
			thisNotePos = ModchartUtil.calculatePerspective(
				_vec3b,
				ModchartUtil.defaultFOV * (Math.PI / 180),
				-(daNote.width / 2),
				-(daNote.height / 2)
			);
		} else {
			_vec3.setTo(noteData.x, noteData.y, 0);
			thisNotePos = _vec3;
		}

		if (daNote.isSustainNote) {
			if (!daNote.animation.curAnim.name.endsWith("end")) {
				noteData.scaleY *= SustainRenderer.sustainScaleMultiplier(daNote, noteData.lane);
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
		daNote.cameras = (noteData.camera != null) ? [noteData.camera] : renderer.cameras;

		var oldX = daNote.x;
		var oldY = daNote.y;
		var oldScaleX = daNote.scale.x;
		var oldScaleY = daNote.scale.y;

		ModchartUtil.applyCameraZoomToSprite(daNote, noteData.camera, noteData.cameraZoom);

		var savedNoteShader = daNote.shader;
		if (noteData.hasColorFill) daNote.shader = null;
		daNote.draw();
		daNote.shader = savedNoteShader;

		daNote.x = oldX;
		daNote.y = oldY;
		daNote.scale.x = oldScaleX;
		daNote.scale.y = oldScaleY;
	}
}
