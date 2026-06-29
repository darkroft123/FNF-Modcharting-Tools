package math;

import flixel.math.FlxPoint;
import flixel.math.FlxAngle;
import flixel.group.FlxSpriteGroup;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import flixel.tweens.FlxEase;
import flixel.FlxSprite;

class TweenGraph extends FlxSpriteGroup {
    public var ease(default, set):EaseFunction = FlxEase.linear;
    private var lerp:Float = 1.0;

    override public function new() {
        super();
        var size = 32;
        for(i in 0...size){
            var sprite:FlxSprite = new FlxSprite();
            sprite.makeSolid(4, 4, FlxColor.interpolate(FlxColor.BLUE, FlxColor.GREEN, i / (size - 1)));
            sprite.ID = i;
            sprite.x = (i / (size - 1)) * 100;
            sprite.origin.set(0, 0);
            add(sprite);
        }
        set_ease(FlxEase.linear);
    }

    override function update(elapsed:Float) {
        super.update(elapsed);
        if(lerp < 1.0){
            lerp += elapsed;
        }
        if(lerp > 1.0){
            lerp = 1.0;
        }
        for(member in members){
            member.y = FlxMath.lerp(member.y, (-ease(member.ID / (length - 1)) * 100) + 100 + y, lerp);
            try{
                var next:FlxPoint = members[members.indexOf(member) + 1].getPosition();
                member.angle = FlxAngle.angleBetweenPoint(member, next, true);
                member.setGraphicSize(Math.sqrt(Math.pow(next.x - member.x, 2) + Math.pow(next.y - member.y, 2)), member.height);
                next.put();
            }
            catch(e){

            }
        }
    }

    @:noCompletion
    private function set_ease(ease:EaseFunction) {
        lerp = 0;
        return this.ease = ease;
    }
}