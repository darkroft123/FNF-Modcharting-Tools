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
using StringTools;

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
    public var loadedValidGraphic:Bool = false;
    public var loadedFrame:Dynamic = null;

    public function updateGraphic(?force:Bool = false):Void {
        if (daNote == null) return;

        var isConnected:Bool = Modifier.SustainConnectModifier.isOutgoingConnected(daNote) || Modifier.SustainConnectModifier.isIncomingConnected(daNote);
        var targetFrame = daNote.frame;

        if (isConnected && daNote.animation != null && daNote.animation.getByName("hold") != null) {
            var hAnim = daNote.animation.getByName("hold");
            if (hAnim != null && hAnim.frames != null && hAnim.frames.length > 0 && daNote.frames != null) {
                var fIdx = (hAnim.frames.length > 1) ? hAnim.frames[1] : hAnim.frames[0];
                if (fIdx >= 0 && fIdx < daNote.frames.frames.length)
                    targetFrame = daNote.frames.frames[fIdx];
            }
        }

        var frameChanged:Bool = (targetFrame != loadedFrame);
        if (!force && !frameChanged && loadedValidGraphic && graphic != null && graphic.bitmap != null && graphic.bitmap.width > 1 && graphic.bitmap.height > 1)
            return;

        try {
            // Keep source frame clean and upright (unflipped) so the GPU mesh handles
            // vertical reflection (reflected sprite) deterministically in both PlayState and Editor.
            var wasFlipped = daNote.flipY;
            daNote.flipY = false;
            var pixels:openfl.display.BitmapData = null;
            if (targetFrame != null && targetFrame.parent != null && targetFrame.parent.bitmap != null) {
                pixels = targetFrame.paint(null, null, false, false);
            }
            if (pixels == null) {
                pixels = daNote.updateFramePixels();
            }
            daNote.flipY = wasFlipped;

            if (pixels != null && pixels.width > 1 && pixels.height > 1) {
                loadGraphic(pixels);
                shader = daNote.shader;
                antialiasing = daNote.antialiasing;
                loadedValidGraphic = true;
                loadedFrame = targetFrame;
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
        var isOutgoing:Bool = Modifier.SustainConnectModifier.isOutgoingConnected(daNote);
        var isIncoming:Bool = Modifier.SustainConnectModifier.isIncomingConnected(daNote);
        var isConnected:Bool = isOutgoing || isIncoming;

        if (!loadedValidGraphic || daNote.frame != loadedFrame || isConnected)
            updateGraphic();

        var yOffset:Float = flipGraphic ? 1 : -1; // fix small rasterizer gaps along scroll direction
        if (reverseClip)
            yOffset *= -1;

        if (cachedVerts.length != 12)
        {
            cachedVerts = [for (i in 0...12) 0.0];
        }

        var thisScale = safeScale(thisNotePos.z) * noteData.scaleX;
        var halfScale = safeScale(nextHalfNotePos.z) * nextHalfNotePos.scaleX;
        var nextScale = safeScale(nextNotePos.z) * nextNotePos.scaleX;

        var baseW0:Float = daNote.frameWidth * thisScale;
        var baseW1:Float = daNote.frameWidth * halfScale;
        var baseW2:Float = daNote.frameWidth * nextScale;

        var wFactor0:Float = 1.0;
        var wFactor1:Float = 1.0;
        var wFactor2:Float = 1.0;

        if (isConnected) {
            var dx:Float = nextNotePos.x - thisNotePos.x;
            var dy:Float = nextNotePos.y - thisNotePos.y;
            var absDy:Float = Math.abs(dy);
            var compFactor:Float = 1.0;
            if (absDy > 1.0 && Math.abs(dx) > 1.0) {
                var dist:Float = Math.sqrt(dx * dx + dy * dy);
                compFactor = dist / absDy;
                if (compFactor > 4.5) compFactor = 4.5;
                if (compFactor < 1.0) compFactor = 1.0;
            }

            if (isOutgoing && isIncoming) {
                wFactor0 = compFactor;
                wFactor1 = compFactor;
                wFactor2 = compFactor;
            } else if (isOutgoing) {
                // Outgoing starts in lane A (factor 1.0) and widens to compFactor at the midpoint
                wFactor0 = 1.0;
                wFactor1 = 1.0 + (compFactor - 1.0) * 0.5;
                wFactor2 = compFactor;
            } else {
                // Incoming starts at compFactor at the midpoint and narrows back to 1.0 in lane B
                wFactor0 = compFactor;
                wFactor1 = 1.0 + (compFactor - 1.0) * 0.5;
                wFactor2 = 1.0;
            }
        }

        var w0:Float = baseW0 * wFactor0;
        var w1:Float = baseW1 * wFactor1;
        var w2:Float = baseW2 * wFactor2;

        var centerX0:Float = thisNotePos.x + (baseW0 * 0.5);
        var centerX1:Float = nextHalfNotePos.x + (baseW1 * 0.5);
        var centerX2:Float = nextNotePos.x + (baseW2 * 0.5);

        // ReflectedSprite-style natural projection:
        // UV y = 0 is the flat base cut, UV y = 1 is the rounded cap.
        // Vertices are symmetrically centered so diagonal slopes maintain
        // uniform perpendicular thickness even across distant lanes (e.g. Left -> Right).
        cachedVerts[0] = centerX0 - (w0 * 0.5);
        cachedVerts[1] = thisNotePos.y + yOffset;
        cachedVerts[2] = centerX0 + (w0 * 0.5);
        cachedVerts[3] = thisNotePos.y + yOffset;

        cachedVerts[4] = centerX1 - (w1 * 0.5);
        cachedVerts[5] = nextHalfNotePos.y + yOffset;
        cachedVerts[6] = centerX1 + (w1 * 0.5);
        cachedVerts[7] = nextHalfNotePos.y + yOffset;

        cachedVerts[8] = centerX2 - (w2 * 0.5);
        cachedVerts[9] = nextNotePos.y + yOffset;
        cachedVerts[10] = centerX2 + (w2 * 0.5);
        cachedVerts[11] = nextNotePos.y + yOffset;

        // Optimized zero-allocation vertex update (no cachedVerts.copy() per frame)
        if (vertices == null || vertices.length != 12)
        {
            vertices = new DrawData(12, true, cachedVerts);
        }
        else
        {
            for (i in 0...12)
                vertices[i] = cachedVerts[i];
        }
    }
}
