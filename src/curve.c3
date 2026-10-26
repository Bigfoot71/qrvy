module qrvy;

import std::math;
import raylib6;

// ================================
// Public: Curve Definitions
// ================================

alias Point = Vec3;

// ================================
// Public: Curve Functions
// ================================

fn void curve_draw(Point[] points, RLRectangle dest, float thickness, RLColor color)
{
	rl::gl_begin(rl::RL_QUADS);
	rl::gl_color4ub(...color);

	for (int i = 0; i < points.len - 1; i++)
	{
		Vec2 p0 = points[i    ].xy;
		Vec2 p1 = points[i + 1].xy;

		p0 = math::fma((Vec2){ p0.x, 1.0f - p0.y }, dest.size, dest.origin);
		p1 = math::fma((Vec2){ p1.x, 1.0f - p1.y }, dest.size, dest.origin);

		quad_line(p0, p1, thickness);
	}

	rl::gl_end();
}

// ================================
// Local: Curve Functions
// ================================

fn void quad_line(Vec2 p0, Vec2 p1, float thickness)
{
	Vec2 dir = (p1 - p0).normalize();
	float half = thickness * 0.5f;
	Vec2 n = dir.yx * { -half, half };

	rl::gl_vertex2f(p0.x - n.x, p0.y - n.y);
	rl::gl_vertex2f(p0.x + n.x, p0.y + n.y);
	rl::gl_vertex2f(p1.x + n.x, p1.y + n.y);
	rl::gl_vertex2f(p1.x - n.x, p1.y - n.y);
}
