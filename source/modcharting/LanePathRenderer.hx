package modcharting;

import flixel.FlxSprite;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxPoint;
import flixel.math.FlxMath;
import openfl.geom.Vector3D;
import flixel.util.FlxColor;

class LanePathRenderer extends FlxSpriteGroup {

	public var renderer:PlayfieldRenderer;
	public var lane:Int;
	public var playfield:Int;

	public var pointCount:Int = 32;
	public var pointSpacing:Float = 50;

	static final FOV:Float = ModchartUtil.defaultFOV * (Math.PI / 180);

	static var tempVec:Vector3D = null;
	var points:Array<FlxPoint> = [];

	public function new(renderer:PlayfieldRenderer, lane:Int, playfield:Int = 0) {
		super();

		this.renderer = renderer;
		this.lane = lane;
		this.playfield = playfield;

		for (i in 0...pointCount)
			points.push(new FlxPoint());

		for (i in 0...pointCount - 1) {
			var seg = new FlxSprite();
			seg.makeGraphic(20, 8, FlxColor.WHITE);
			seg.origin.set(10, 4);
			add(seg);
		}
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (renderer == null || renderer.modifierTable == null || renderer.playfields == null || renderer.playfields[playfield] == null)
			return;

		var modifierTable = renderer.modifierTable;
		var pfObj = renderer.playfields[playfield];

		var baseX = 0.0;
		var baseY = 0.0;
		if (NoteMovement.defaultStrumX != null && lane < NoteMovement.defaultStrumX.length)
			baseX = NoteMovement.defaultStrumX[lane];
		if (NoteMovement.defaultStrumY != null && lane < NoteMovement.defaultStrumY.length)
			baseY = NoteMovement.defaultStrumY[lane];

		var step = pointSpacing;

		var noteSize = 112.0;
		if (NoteMovement.arrowSizes != null && lane < NoteMovement.arrowSizes.length)
			noteSize = NoteMovement.arrowSizes[lane];
		var noteSizeHalf = noteSize / 2;

		var i = 0;
		var pt = points;

		while (i < pointCount) {

			var curPos = -i * step;
			curPos = modifierTable.applyCurPosMods(lane, curPos, playfield);

			var noteDist = -0.45;
			if (renderer.isDownscroll)
				noteDist *= -1;
			noteDist = modifierTable.applyNoteDistMods(noteDist, lane, playfield);

			var ang = modifierTable.applyIncomingAngleMods(lane, curPos, playfield);

			var angleX = (noteDist < 0) ? ang[0] + 180 : ang[0];
			var angleY = ang[1];

			// 3D base transform FIRST
			var pos = ModchartUtil.getCartesianCoords3D(angleX, angleY, curPos * noteDist);

			var x = baseX + pos.x;
			var y = baseY + pos.y;
			var z = pos.z;

			// apply playfield offsets (logical space only)
			var tmpData = NotePositionData.get();
			tmpData.setupNote(
				x, y, z,
				lane,
				1, 1,
				0, 0,
				playfield,
				1,
				curPos,
				noteDist,
				angleX,
				angleY,
				0,
				-1
			);

			pfObj.applyOffsets(tmpData);
			modifierTable.applyNoteMods(tmpData, lane, curPos, playfield);

			// FINAL 3D POSITION (after mods)
			var thisNotePos:Vector3D;
			if (tmpData.z != 0) {
				if (tempVec == null) tempVec = new Vector3D();
				tempVec.setTo(tmpData.x + noteSizeHalf, tmpData.y + noteSizeHalf, tmpData.z * 0.001);
				thisNotePos = ModchartUtil.calculatePerspective(
					tempVec,
					FOV,
					-noteSizeHalf,
					-noteSizeHalf
				);
			} else {
				if (tempVec == null) tempVec = new Vector3D();
				tempVec.setTo(tmpData.x, tmpData.y, 0);
				thisNotePos = tempVec;
			}

			pt[i].set(thisNotePos.x + noteSizeHalf, thisNotePos.y + noteSizeHalf);

			NotePositionData.recycle(tmpData);

			i++;
		}

		// draw segments
		var j = 0;
		var segs = members;

		while (j < pointCount - 1) {

			var seg:FlxSprite = cast segs[j];
			if (seg == null) {
				j++;
				continue;
			}

			var p1 = pt[j];
			var p2 = pt[j + 1];

			var dx = p2.x - p1.x;
			var dy = p2.y - p1.y;

			seg.visible = true;

			// alpha más estable (evita flicker en perspectiva extrema)
			var dist = FlxMath.vectorLength(dx, dy);
			var depthAlpha = 1 / (1 + dist * 0.002);
			var pfAlpha = (renderer.playfields != null && playfield < renderer.playfields.length) ? renderer.playfields[playfield].alpha : 1;
			seg.alpha = FlxMath.bound(depthAlpha, 0.25, 1) * pfAlpha;

			var midX = (p1.x + p2.x) / 2;
			var midY = (p1.y + p2.y) / 2;

			var size = Std.int(Math.max(dist, 4));
			seg.setGraphicSize(size, 8);
			seg.updateHitbox();

			seg.x = midX - (size / 2);
			seg.y = midY - 4;

			seg.angle = Math.atan2(dy, dx) * 57.2957795;

			j++;
		}
	}
}