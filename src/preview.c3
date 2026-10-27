module qrvy;

import std::math;
import raylib6;
import rlp;

// ================================
// Constants
// ================================

const float PREVIEW_FADE_TIME = 0.6f;

// ================================
// State
// ================================

struct Preview
{
	bool     active;
	float    fade;        // 0 = editor only, 1 = animation only
	float    time;        // seconds since opening
	RLShader shader;
	bool     loaded;
	int      loc_time;
	int      loc_res;
}

// ================================
// Public: Preview Functions
// ================================

fn bool preview_open()
{
	generate();
	preview_free();

	RLShader shader;
	@pool()
	{
		DString fs = dstring::temp();
		fs.appendf("#define EASE %s\n", EASE_NAME);
		fs.append(PREVIEW_HEAD);
		fs.append(ctx.code.str_view());
		fs.append(PREVIEW_SCENE);

		shader = rlp::load_shader_from_memory({}, fs.str_view());
	};

	int loc_time = shader.get_location("uTime");
	int loc_res  = shader.get_location("uResolution");

	if (loc_time < 0 || loc_res < 0)
	{
		rl::unload_shader(shader);
		return false;
	}

	ctx.preview = {
		.active   = true,
		.shader   = shader,
		.loaded   = true,
		.loc_time = loc_time,
		.loc_res  = loc_res,
	};
	return true;
}

fn void preview_free()
{
	if (ctx.preview.loaded) rl::unload_shader(ctx.preview.shader);
	ctx.preview = {};
}

fn void preview_update(float dt)
{
	Preview* p = &ctx.preview;

	if (rl::is_mouse_button_pressed(LEFT) || rl::is_mouse_button_pressed(RIGHT))
	{
		p.active = false;
		p.fade = 0.0f;
		return;
	}

	p.time += dt;
	p.fade = math::min(p.fade + dt / PREVIEW_FADE_TIME, 1.0f);
}

fn void preview_draw(float w, float h)
{
	Preview* p = &ctx.preview;

	float fade = math::clamp(p.fade * 2.0f, 0.0f, 1.0f);
	float anim = math::clamp(p.fade * 2.0f - 1.0f, 0.0f, 1.0f);

	rl::draw_rectangle(0, 0, (int)w, (int)h, (RLColor){0, 34, 43, 255}.fade(fade)); //< color same as BACKGROUND_COLOR of raygui's cyber theme

	if (anim <= 0.0f) return;

	float t = math::max(p.time - PREVIEW_FADE_TIME * 0.5f, 0.0f);
	Vec2 res = { w, h };
	p.shader.set_value(p.loc_time, &t, FLOAT);
	p.shader.set_value(p.loc_res, &res, VEC2);

	rl::begin_shader_mode(p.shader);
	rl::gl_begin(rl::RL_QUADS);
	rl::gl_color4ub(255, 255, 255, (char)(anim * 255.0f));
	rl::gl_tex_coord2f(0.0f, 1.0f); rl::gl_vertex2f(0.0f, 0.0f);
	rl::gl_tex_coord2f(0.0f, 0.0f); rl::gl_vertex2f(0.0f, h);
	rl::gl_tex_coord2f(1.0f, 0.0f); rl::gl_vertex2f(w, h);
	rl::gl_tex_coord2f(1.0f, 1.0f); rl::gl_vertex2f(w, 0.0f);
	rl::gl_end();
	rl::end_shader_mode();
}

// ================================
// Local: Preview Shader
// ================================

const String PREVIEW_HEAD @local = `
precision highp float;

IN vec2 fragTexCoord;
IN vec4 fragColor;

uniform float uTime;
uniform vec2  uResolution;
`;

const String PREVIEW_SCENE @local = `

// Constants (inspired from raygui's cyber theme)
const vec3 BACKGROUND = vec3(0.00, 0.016, 0.024);
const vec3 FLOOR      = vec3(0.00, 0.064, 0.096);
const vec3 LINE       = vec3(1.00, 0.114, 0.000);

// Animation state
float g_p; // linear progress, 0..1
float g_e; // eased progress: EASE(g_p)
float g_x; // x of the sphere

vec3 pal(float t)
{
	return 0.5 + 0.5 * cos(TAU * (t + vec3(0.0, 0.33, 0.67)));
}

mat2 rot(float a)
{
	float c = cos(a);
	float s = sin(a);
	return mat2(c, -s, s, c);
}

float sdSphere(vec3 p, float r)
{
	return length(p) - r;
}

float map(vec3 p) // Distance to the sphere only
{
	return sdSphere(p - vec3(g_x, 0.0, 0.0), 0.5);
}

float sphereShadow(vec3 pos, vec3 l, vec3 c, float r)
{
	vec3 oc = c - pos;
	float tca = dot(oc, l);
	float d = length(oc - l * tca);
	return tca > 0.0 ? smoothstep(r * 0.6, r * 1.6, d) : 1.0;
}

float dither(vec2 pos)
{
    // http://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare
    const vec3 magic = vec3(0.06711056, 0.00583715, 52.9829189);
    return fract(magic.z * fract(dot(pos, magic.xy)));
}

vec3 debanding(vec2 pos, vec3 color)
{
    const float dither_strength = 1.0 / 255.0;
    float n = dither(pos.xy);
    float d = (n - 0.5) * dither_strength;
    return color + d;
}

void main()
{
	vec2 uv      = fragTexCoord;
	float aspect = uResolution.x / uResolution.y;
	vec2 pxc     = (uv - 0.5) * vec2(aspect, 1.0);

	// Timeline: forward, hold, backward, hold (4 seconds)
	float ph  = fract(uTime / 4.0);
	float tri = 1.0 - abs(2.0 * ph - 1.0);

	g_p = saturate((tri - 0.1) / 0.8);
	g_e = EASE(g_p);
	g_x = mix(-2.6, 2.6, g_e);

	// Camera (sway)
	vec3 ro = vec3(0.0, 1.3, -6.0 * max(1.0, 1.7 / aspect));
	ro.xz = rot(0.25 * sin(uTime * 0.4)) * ro.xz;

	vec3 fwd   = normalize(vec3(0.0, -0.1, 0.0) - ro);
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	vec3 upv   = cross(fwd, right);
	vec3 rd    = normalize(fwd * 1.5 + right * pxc.x + upv * pxc.y);

	// Floor
	float tf   = rd.y < -0.0001 ? (-0.5 - ro.y) / rd.y : 1e9;
	float tmax = min(tf, 30.0);

	// Raymarching the sphere
	float t = 0.0;
	bool hitSphere = false;
	for (int i = 0; i < 64; i++)
	{
		float d = map(ro + rd * t);
		if (d < 0.001) { hitSphere = true; break; }
		t += d;
		if (t > tmax) break;
	}

	// Shading
	vec3 col = mix(BACKGROUND * 0.5, BACKGROUND, uv.y);
	col *= 1.0 - 0.7 * dot(pxc, pxc);

	vec3 l = normalize(vec3(-0.5, 0.9, -0.6));
	vec3 c = vec3(g_x, 0.0, 0.0);

	if (hitSphere)
	{
		vec3 pos = ro + rd * t;
		vec3 n   = normalize(pos - c);
		vec3 base = pal(g_e);

		float diff = saturate(dot(n, l));
		float spec = pow(saturate(dot(reflect(rd, n), l)), 32.0);
		float fre  = pow(1.0 - saturate(dot(n, -rd)), 3.0);

		col = base * (0.15 + 0.85 * diff) + spec * 0.5 + fre * base * 0.5;
	}
	else if (tf < 30.0)
	{
		vec3 pos = ro + rd * tf;

		// Edges lines
		float w    = 0.03 + 0.012 * tf;
		float ends = 1.0 - smoothstep(0.0, w, abs(abs(pos.x) - 2.6));
		vec3 base  = FLOOR + LINE * ends;

		float diff = saturate(l.y) * sphereShadow(pos, l, c, 0.5);
		vec3 lit   = base * (0.15 + 0.85 * diff);

		// Blending with the horizon
		col = mix(col, lit, exp(-0.07 * tf));
	}

	col = pow(clamp(col, 0.0, 1.0), vec3(0.4545));

	// Curve plot
	float S = 0.26 * uResolution.y;
	vec2  q = (uv * uResolution - vec2(0.04 * uResolution.y)) / S;
	if (q.x > -0.08 && q.x < 1.08 && q.y > -0.08 && q.y < 1.08)
	{
		float u = 1.0 / S; // one pixel; in plot units
		bool inside  = q.x >= 0.0 && q.x <= 1.0 && q.y >= 0.0 && q.y <= 1.0;
		bool onFrame = q.x >= -2.0 * u && q.x <= 1.0 + 2.0 * u && q.y >= -2.0 * u && q.y <= 1.0 + 2.0 * u;

		col = mix(col, vec3(0.0), 0.65);

		// Grid every 0.25, linear reference, frame
		vec2 gd = abs(fract(q * 4.0 + 0.5) - 0.5) / 4.0;
		vec2 fd = min(abs(q), abs(q - 1.0));
		float grid  = 1.0 - smoothstep(0.0, 1.5 * u, min(gd.x, gd.y));
		float diag  = 1.0 - smoothstep(0.0, 1.5 * u, abs(q.y - q.x) * 0.7071);
		float frame = 1.0 - smoothstep(0.0, 1.5 * u, min(fd.x, fd.y));
		if (inside)  col = mix(col, vec3(1.0), grid * 0.08 + diag * 0.12);
		if (onFrame) col = mix(col, vec3(1.0), frame * 0.5);

		// The curve
		if (inside)
		{
			float f  = EASE(q.x);
			float hh = 0.004;
			float df = (EASE(min(q.x + hh, 1.0)) - EASE(max(q.x - hh, 0.0))) / (2.0 * hh);
			float d  = abs(q.y - f) / sqrt(1.0 + df * df);
			col = mix(col, vec3(1.0, 0.72, 0.28), 1.0 - smoothstep(0.8 * u, 2.0 * u, d));
		}

		// Current progress
		float vx = (1.0 - smoothstep(0.0, 1.2 * u, abs(q.x - g_p))) * step(0.0, q.y) * step(q.y, g_e);
		float hy = (1.0 - smoothstep(0.0, 1.2 * u, abs(q.y - g_e))) * step(0.0, q.x) * step(q.x, g_p);
		col = mix(col, vec3(1.0), max(vx, hy) * 0.35);

		float dd = length((q - vec2(g_p, g_e)) * S);
		col = mix(col, pal(g_e), 1.0 - smoothstep(4.0, 5.5, dd));
	}

	col = debanding(gl_FragCoord.xy, col);

	FRAG_COLOR = vec4(col, fragColor.a);
}
`;
