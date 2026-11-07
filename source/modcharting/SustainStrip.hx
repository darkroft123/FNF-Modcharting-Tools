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
        var isConnected:Bool = Modifier.SustainConnectModifier.isOutgoingConnected(daNote) || Modifier.SustainConnectModifier.isIncomingConnected(daNote);
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

        // ReflectedSprite-style natural projection:
        // UV y = 0 is the flat base cut, UV y = 1 is the rounded cap.
        // thisNotePos is always the base (anchored at note head / previous piece).
        // nextNotePos is always the tail (extending along the scroll path).
        // In Upscroll: thisNotePos is top, nextNotePos is bottom -> base at top, cap at bottom.
        // In Downscroll: thisNotePos is bottom, nextNotePos is top -> base at bottom, cap at top (reflected).
        cachedVerts[0] = thisNotePos.x;
        cachedVerts[1] = thisNotePos.y + yOffset;
        cachedVerts[2] = thisNotePos.x + (daNote.frameWidth * thisScale);
        cachedVerts[3] = thisNotePos.y + yOffset;

        cachedVerts[4] = nextHalfNotePos.x;
        cachedVerts[5] = nextHalfNotePos.y + yOffset;
        cachedVerts[6] = nextHalfNotePos.x + (daNote.frameWidth * halfScale);
        cachedVerts[7] = nextHalfNotePos.y + yOffset;

        cachedVerts[8] = nextNotePos.x;
        cachedVerts[9] = nextNotePos.y + yOffset;
        cachedVerts[10] = nextNotePos.x + (daNote.frameWidth * nextScale);
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