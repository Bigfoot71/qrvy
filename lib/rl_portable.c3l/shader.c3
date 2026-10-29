module rlp;

import raylib6;

// Available helpers (all versions):
//
// I/O
//   IN, OUT                 - attribute/varying qualifiers
//   FRAG_COLOR              - fragment shader color output (loc: 0)
//
// Sampling
//   TEXTURE_2D(s,uv)        - sampler2D
//   TEXTURE_CUBE(s,uv)      - samplerCube
//
// Precision (no-op on desktop GL)
//   HIGHP, MEDIUMP, LOWP
//
// Math
//   saturate(x)             - clamp(x, 0, 1)
//   remap(v,a,b,c,d)        - remap v from [a,b] to [c,d]
//
// Constants
//   PI, TAU, HALF_PI, INV_PI, SQRT2

// ================================
// Public: Shader Functions
// ================================

fn RLShader load_shader(String vs_file, String fs_file) => @pool()
{
	ZString vs_code = vs_file.len > 0 ? rl::load_file_text(vs_file.zstr_tcopy()) : null;
	ZString fs_code = fs_file.len > 0 ? rl::load_file_text(fs_file.zstr_tcopy()) : null;

	defer free(vs_code);
	defer free(fs_code);

	return load_shader_from_memory(
		vs_code ? vs_code.str_view() : "",
		fs_code ? fs_code.str_view() : "");
}

fn RLShader load_shader_from_memory(String vs_code, String fs_code) => @pool()
{
	RLGlVersion version = (RLGlVersion)rl::gl_get_version();

	if (version == OPENGL_11) return {};

	DString vs_final = dstring::temp();
	DString fs_final = dstring::temp();

	if (vs_code.len > 0)
	{
		vs_final.append(shader_header_vert(version));
		vs_final.append(vs_code);
	}

	if (fs_code.len > 0)
	{
		fs_final.append(shader_header_frag(version));
		fs_final.append(fs_code);
	}

	return rl::load_shader_from_memory(
		vs_code.len > 0 ? vs_final.zstr_view() : null,
		fs_code.len > 0 ? fs_final.zstr_view() : null);
}

// ================================
// Local: Header Selection
// ================================

fn String shader_header_vert(RLGlVersion version) @local
{
	switch (version)
	{
		case OPENGL_21:    return SHADER_HEADER_VERT_GL21;
		case OPENGL_ES_20: return SHADER_HEADER_VERT_ES20;
		case OPENGL_ES_30: return SHADER_HEADER_VERT_ES30;
		default:           return SHADER_HEADER_VERT_GL33; // 33 and 43 (GLSL 330)
	}
}

fn String shader_header_frag(RLGlVersion version) @local
{
	switch (version)
	{
		case OPENGL_21:    return SHADER_HEADER_FRAG_GL21;
		case OPENGL_ES_20: return SHADER_HEADER_FRAG_ES20;
		case OPENGL_ES_30: return SHADER_HEADER_FRAG_ES30;
		default:           return SHADER_HEADER_FRAG_GL33; // 33 and 43 (GLSL 330)
	}
}

// ================================
// Local: Shader Helpers
// ================================

const String SHADER_HELPERS @local = `
#define saturate(x) clamp((x), 0.0, 1.0)
#define remap(v,a,b,c,d) mix((c),(d),((v)-(a))/((b)-(a)))
#define PI 3.14159265358979323846
#define TAU 6.28318530717958647692
#define HALF_PI 1.57079632679489661923
#define INV_PI 0.31830988618379067154
#define SQRT2 1.41421356237309504880
`;

// ================================
// Local: OpenGL 2.1
// ================================

const String SHADER_HEADER_VERT_GL21 @local = `#version 120
#define IN attribute
#define OUT varying
#define TEXTURE_2D texture2D
#define TEXTURE_CUBE textureCube
#define HIGHP
#define MEDIUMP
#define LOWP
#define _VERT` +++ SHADER_HELPERS;

const String SHADER_HEADER_FRAG_GL21 @local = `#version 120
#define IN varying
#define FRAG_COLOR gl_FragColor
#define TEXTURE_2D texture2D
#define TEXTURE_CUBE textureCube
#define HIGHP
#define MEDIUMP
#define LOWP
#define _FRAG` +++ SHADER_HELPERS;

// ================================
// Local: OpenGL 3.3 / 4.3
// ================================

const String SHADER_HEADER_VERT_GL33 @local = `#version 330
#define IN in
#define OUT out
#define TEXTURE_2D texture
#define TEXTURE_CUBE texture
#define HIGHP
#define MEDIUMP
#define LOWP
#define _VERT` +++ SHADER_HELPERS;

const String SHADER_HEADER_FRAG_GL33 @local = `#version 330
#define IN in
layout(location = 0) out vec4 FRAG_COLOR;
#define TEXTURE_2D texture
#define TEXTURE_CUBE texture
#define HIGHP
#define MEDIUMP
#define LOWP
#define _FRAG` +++ SHADER_HELPERS;

// ================================
// Local: OpenGL ES 2.0 / WebGL 1
// ================================

const String SHADER_HEADER_VERT_ES20 @local = `#version 100
precision mediump float;
#define IN attribute
#define OUT varying
#define TEXTURE_2D texture2D
#define TEXTURE_CUBE textureCube
#define HIGHP highp
#define MEDIUMP mediump
#define LOWP lowp
#define _VERT` +++ SHADER_HELPERS;

const String SHADER_HEADER_FRAG_ES20 @local = `#version 100
precision mediump float;
#define IN varying
#define FRAG_COLOR gl_FragColor
#define TEXTURE_2D texture2D
#define TEXTURE_CUBE textureCube
#define HIGHP highp
#define MEDIUMP mediump
#define LOWP lowp
#define _FRAG` +++ SHADER_HELPERS;

// ================================
// Local: OpenGL ES 3.0 / WebGL 2
// ================================

const String SHADER_HEADER_VERT_ES30 @local = `#version 300 es
precision mediump float;
#define IN in
#define OUT out
#define TEXTURE_2D texture
#define TEXTURE_CUBE texture
#define HIGHP highp
#define MEDIUMP mediump
#define LOWP lowp
#define _VERT` +++ SHADER_HELPERS;

const String SHADER_HEADER_FRAG_ES30 @local = `#version 300 es
precision mediump float;
#define IN in
layout(location = 0) out vec4 FRAG_COLOR;
#define TEXTURE_2D texture
#define TEXTURE_CUBE texture
#define HIGHP highp
#define MEDIUMP mediump
#define LOWP lowp
#define _FRAG` +++ SHADER_HELPERS;
