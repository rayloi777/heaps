// heaps/tests/hlmetal/ShaderMathBasic.hx
// All @:hxsl test shader classes for the hlmetal test suite
// Note: all computed values must be used in the output to survive HxSL DCE.

// ---- Test 1: MathBasic ----
// Exercises: Sin, Cos, Pow, Abs, Sqrt, Min, Max, Clamp, Saturate
class ShaderMathBasic extends hxsl.Shader {
    static var SRC = {
        @input var input : { position : Vec3 };
        @param var time : Float;
        var output : { position : Vec4, color : Vec4 };

        function vertex() {
            output.position = vec4(input.position, 1.0);
        }

        function fragment() {
            var s = sin(time);
            var c = cos(time);
            var p = pow(abs(s), 2.0);
            var sq = sqrt(p);
            var mn = min(s, c);
            var mx = max(s, c);
            var cl = clamp(s, -1.0, 1.0);
            var sat = saturate(s);
            output.color = vec4(s + mn + cl, c + mx, sq, p + sat);
        }
    };
}

// ---- Test 2: MathAdvanced ----
// Exercises: Fract, Mix, Step, Smoothstep, Reflect, Normalize, Length, Dot, Cross
class ShaderMathAdvanced extends hxsl.Shader {
    static var SRC = {
        @input var input : { position : Vec3 };
        @param var time : Float;
        var output : { position : Vec4, color : Vec4 };

        function vertex() {
            output.position = vec4(input.position, 1.0);
        }

        function fragment() {
            var f = fract(time);
            var m = mix(vec3(0.0), vec3(1.0), 0.5);
            var st = step(0.5, f);
            var ss = smoothstep(0.0, 1.0, f);
            var d = dot(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0));
            var cr = cross(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0));
            var n = normalize(vec3(1.0, 1.0, 0.0));
            var l = length(vec3(1.0, 1.0, 0.0));
            var r = reflect(vec3(1.0, -1.0, 0.0), vec3(0.0, 1.0, 0.0));
            // Use all values in output to survive DCE
            output.color = vec4(f + st + d + l, ss + m.x + m.y + m.z, n.x + cr.x + r.x, n.y + cr.y + r.y);
        }
    };
}

// ---- Test 3: VecMatOps ----
// Exercises: Vec2-4, Mat2-4, Transpose, matrix multiply
class ShaderVecMatOps extends hxsl.Shader {
    static var SRC = {
        @input var input : { position : Vec3 };
        @param var mvp : Mat4;
        var output : { position : Vec4, color : Vec4 };

        function vertex() {
            var v2 = vec2(1.0, 2.0);
            var v3 = vec3(1.0, 2.0, 3.0);
            var v4 = vec4(1.0, 2.0, 3.0, 4.0);
            var m2 = mat2(1.0, 0.0, 0.0, 1.0);
            var m3 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
            var m4 = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
            var t = transpose(m3);
            var transformed = vec4(input.position, 1.0) * mvp;
            output.position = transformed + v4;
        }

        function fragment() {
            var v2 = vec2(1.0, 2.0);
            var m2 = mat2(1.0, 0.0, 0.0, 1.0);
            var m3 = mat3(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0);
            var t = transpose(m3);
            output.color = vec4(v2.x + t[0][0] + t[1][1] + t[2][2], v2.y, m2[0][0] + m2[1][1], 1.0);
        }
    };
}

// ---- Test 4: TypeConv ----
// Exercises: int(), float(), toBool()
class ShaderTypeConv extends hxsl.Shader {
    static var SRC = {
        @input var input : { position : Vec3 };
        @param var value : Float;
        var output : { position : Vec4, color : Vec4 };

        function vertex() {
            output.position = vec4(input.position, 1.0);
        }

        function fragment() {
            var i = int(value);
            var f = float(i);
            var b = toBool(i);
            output.color = vec4(f, float(i) + float(b), 0.0, 1.0);
        }
    };
}
