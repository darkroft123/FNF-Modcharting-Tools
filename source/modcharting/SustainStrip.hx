package modcharting;

import flixel.graphics.tile.FlxDrawTrianglesItem.DrawData;
import openfl.geom.Vector3D;
#if LEATHER
import game.Note;
#elseif (PSYCH && PSYCHVERSION >= "0.7")
import objects.Note;
#else
import Note;
#end
import flixel.FlxStrip;

class SustainStrip extends FlxStrip
{
    public static final noteUV:Array<Float> = [
        0,0, //top left
        1,0, //top right
        0,0.5, //half left
        1,0.5, //half right    
        0,1, //bottom left
        1,1, //bottom right 
    ];
    public static final noteIndices:Array<Int> = [
        0,1,2,1,3,2, 2,3,4,3,4,5
        //makes 4 triangles
    ];

    public var daNote:Note;
    var cachedVerts:Array<Float> = [];

    override public function new(daNote:Note)
    {
        this.daNote = daNote;
        daNote.alpha = 1;
        super(0,0);
        loadGraphic(daNote.updateFramePixels());
        shader = daNote.shader;
        antialiasing = daNote.antialiasing;
        for (uv in noteUV)
        {
            uvtData.push(uv);
            vertices.push(0);
        }
        for (ind in noteIndices)
            indices.push(ind);
    }

    public function constructVertices(noteData:NotePositionData, thisNotePos:Vector3D, nextHalfNotePos:NotePositionData, nextNotePos:NotePositionData, flipGraphic:Bool, reverseClip:Bool)
    {
        var yOffset = -1; //fix small gaps
        if (reverseClip)
            yOffset *= -1;

        if (cachedVerts.length != 12)
        {
            for (i in 0...12)
                cachedVerts.push(0);
        }

        if (flipGraphic)
        {
            cachedVerts[0] = nextNotePos.x;
            cachedVerts[1] = nextNotePos.y;
            cachedVerts[2] = nextNotePos.x+(daNote.frameWidth*(1/-nextNotePos.z)*noteData.scaleX);
            cachedVerts[3] = nextNotePos.y;

            cachedVerts[4] = nextHalfNotePos.x;
            cachedVerts[5] = nextHalfNotePos.y;
            cachedVerts[6] = nextHalfNotePos.x+(daNote.frameWidth*(1/-nextHalfNotePos.z)*noteData.scaleX);
            cachedVerts[7] = nextHalfNotePos.y;

            cachedVerts[8] = thisNotePos.x;
            cachedVerts[9] = thisNotePos.y;
            cachedVerts[10] = thisNotePos.x+(daNote.frameWidth*(1/-thisNotePos.z)*nextNotePos.scaleX);
            cachedVerts[11] = thisNotePos.y;
        }
        else 
        {
            cachedVerts[0] = thisNotePos.x;
            cachedVerts[1] = thisNotePos.y;
            cachedVerts[2] = thisNotePos.x+(daNote.frameWidth*(1/-thisNotePos.z)*noteData.scaleX);
            cachedVerts[3] = thisNotePos.y;

            cachedVerts[4] = nextHalfNotePos.x;
            cachedVerts[5] = nextHalfNotePos.y;
            cachedVerts[6] = nextHalfNotePos.x+(daNote.frameWidth*(1/-nextHalfNotePos.z)*noteData.scaleX);
            cachedVerts[7] = nextHalfNotePos.y;

            cachedVerts[8] = nextNotePos.x;
            cachedVerts[9] = nextNotePos.y;
            cachedVerts[10] = nextNotePos.x+(daNote.frameWidth*(1/-nextNotePos.z)*nextNotePos.scaleX);
            cachedVerts[11] = nextNotePos.y;
        }
        vertices = new DrawData(12, true, cachedVerts.copy());
    }
}