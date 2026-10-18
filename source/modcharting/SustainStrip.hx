package modcharting;

import flixel.graphics.tile.FlxDrawTrianglesItem.DrawData;
import openfl.geom.Vector3D;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;
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
    public static var showHitboxContainers:Bool = true;
    private static var containerCache:Map<String, BitmapData> = new Map();

    public static function getHitboxContainerGraphic(lane:Int, isHoldEnd:Bool):BitmapData
    {
        var key:String = (lane % 4) + "_" + (isHoldEnd ? "end" : "hold");
        if (containerCache.exists(key))
            return containerCache.get(key);

        var size:Int = 128;
        var b:BitmapData = new BitmapData(size, size, true, 0x00000000);

        // Lane colors: 0: purple, 1: blue/cyan, 2: green, 3: red
        var laneColors:Array<Int> = [0xFFC24B99, 0xFF00FFFF, 0xFF12FA05, 0xFFF9393F];
        var col:Int = laneColors[lane % 4];

        // Semi-transparent background
        var fillAlpha:Int = isHoldEnd ? 0x55000000 : 0x38000000;
        var fillColor:Int = (col & 0x00FFFFFF) | fillAlpha;
        b.fillRect(new Rectangle(0, 0, size, size), fillColor);

        // Outer container border (4px)
        var borderThick:Int = 4;
        b.fillRect(new Rectangle(0, 0, size, borderThick), col);
        b.fillRect(new Rectangle(0, size - borderThick, size, borderThick), col);
        b.fillRect(new Rectangle(0, 0, borderThick, size), col);
        b.fillRect(new Rectangle(size - borderThick, 0, borderThick, size), col);

        // Center lines/grid to visualize the container alignment
        var midX:Int = Std.int(size / 2);
        var midY:Int = Std.int(size / 2);
        b.fillRect(new Rectangle(4, midY - 1, size - 8, 2), (col & 0x00FFFFFF) | 0x88000000);
        b.fillRect(new Rectangle(midX - 1, 4, 2, size - 8), (col & 0x00FFFFFF) | 0x88000000);

        if (isHoldEnd)
        {
            // Flat connection edge (top) marked with solid white bar
            b.fillRect(new Rectangle(0, 0, size, 6), 0xFFFFFFFF);
            // Cap edge (bottom) marked with bright warning/cap block
            b.fillRect(new Rectangle(12, size - 22, size - 24, 18), 0xFFFFEE00);
            b.fillRect(new Rectangle(28, size - 36, size - 56, 12), 0xFFFFCC00);
            b.fillRect(new Rectangle(44, size - 46, size - 88, 8), 0xFFFFFFFF);
        }
        else
        {
            // Hold body: connection edge markers on both ends
            b.fillRect(new Rectangle(0, 0, size, 4), 0xFFFFFFFF);
            b.fillRect(new Rectangle(0, size - 4, size, 4), 0xFFFFFFFF);
        }

        containerCache.set(key, b);
        return b;
    }

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
    public var loadedValidGraphic:Bool = false;
    public var loadedFrame:Dynamic = null;

    public function updateGraphic(?force:Bool = false):Void {
        if (daNote == null) return;

        var animName:String = (daNote.animation.curAnim != null) ? daNote.animation.curAnim.name : "";
        var isHoldEnd:Bool = animName.endsWith("end");

        if (showHitboxContainers)
        {
            var bmp = getHitboxContainerGraphic(daNote.noteData, isHoldEnd);
            loadGraphic(bmp);
            shader = null;
            antialiasing = false;
            loadedValidGraphic = true;
            loadedFrame = null;
            return;
        }

        var frameChanged:Bool = (daNote.frame != loadedFrame);
        if (!force && !frameChanged && loadedValidGraphic && graphic != null && graphic.bitmap != null && graphic.bitmap.width > 1 && graphic.bitmap.height > 1)
            return;

        try {
            var pixels = daNote.updateFramePixels();
            if (pixels == null) {
                var frame = daNote.frame;
                if (frame != null && frame.parent != null && frame.parent.bitmap != null)
                    pixels = frame.paint();
            }
            if (pixels != null && pixels.width > 1 && pixels.height > 1) {
                loadGraphic(pixels);
                shader = daNote.shader;
                antialiasing = daNote.antialiasing;
                loadedValidGraphic = true;
                loadedFrame = daNote.frame;
            }
        } catch (e:Dynamic) {}
    }

    override public function new(daNote:Note)
    {
        this.daNote = daNote;
        daNote.alpha = 1;
        super(0,0);
        updateGraphic(true);
        for (uv in noteUV)
        {
            uvtData.push(uv);
            vertices.push(0);
        }
        for (ind in noteIndices)
            indices.push(ind);
    }

    static inline function safeScale(z:Float):Float {
        return (z > -0.001 && z < 0.001) ? 1.0 : (1.0 / -z);
    }

    override public function draw():Void {
        super.draw();
    }

    override public function destroy():Void {
        super.destroy();
    }

    public function constructVertices(noteData:NotePositionData, thisNotePos:Vector3D, nextHalfNotePos:NotePositionData, nextNotePos:NotePositionData, flipGraphic:Bool, reverseClip:Bool)
    {
        if (!loadedValidGraphic)
            updateGraphic();

        var yOffset = -1; //fix small gaps
        if (reverseClip)
            yOffset *= -1;

        if (cachedVerts.length != 12)
        {
            for (i in 0...12)
                cachedVerts.push(0);
        }

        var thisScale = safeScale(thisNotePos.z) * noteData.scaleX;
        var halfScale = safeScale(nextHalfNotePos.z) * nextHalfNotePos.scaleX;
        var nextScale = safeScale(nextNotePos.z) * nextNotePos.scaleX;

        if (flipGraphic)
        {
            cachedVerts[0] = nextNotePos.x;
            cachedVerts[1] = nextNotePos.y + yOffset;
            cachedVerts[2] = nextNotePos.x+(daNote.frameWidth*nextScale);
            cachedVerts[3] = nextNotePos.y + yOffset;

            cachedVerts[4] = nextHalfNotePos.x;
            cachedVerts[5] = nextHalfNotePos.y + yOffset;
            cachedVerts[6] = nextHalfNotePos.x+(daNote.frameWidth*halfScale);
            cachedVerts[7] = nextHalfNotePos.y + yOffset;

            cachedVerts[8] = thisNotePos.x;
            cachedVerts[9] = thisNotePos.y + yOffset;
            cachedVerts[10] = thisNotePos.x+(daNote.frameWidth*thisScale);
            cachedVerts[11] = thisNotePos.y + yOffset;
        }
        else 
        {
            cachedVerts[0] = thisNotePos.x;
            cachedVerts[1] = thisNotePos.y + yOffset;
            cachedVerts[2] = thisNotePos.x+(daNote.frameWidth*thisScale);
            cachedVerts[3] = thisNotePos.y + yOffset;

            cachedVerts[4] = nextHalfNotePos.x;
            cachedVerts[5] = nextHalfNotePos.y + yOffset;
            cachedVerts[6] = nextHalfNotePos.x+(daNote.frameWidth*halfScale);
            cachedVerts[7] = nextHalfNotePos.y + yOffset;

            cachedVerts[8] = nextNotePos.x;
            cachedVerts[9] = nextNotePos.y + yOffset;
            cachedVerts[10] = nextNotePos.x+(daNote.frameWidth*nextScale);
            cachedVerts[11] = nextNotePos.y + yOffset;
        }
        vertices = new DrawData(12, true, cachedVerts.copy());
    }
}
