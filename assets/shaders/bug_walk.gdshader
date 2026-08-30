shader_type canvas_item;
// Bug gait wobble: a scuttling rotation + counter-phase squash, entirely on
// the GPU — zero per-bug CPU cost at any horde size. `phase` desyncs
// neighbors; `freq` scales with the bug's move speed; `strength` lets a
// type tone the wobble down (boss).

uniform float phase = 0.0;
uniform float freq = 9.0;
uniform float strength = 1.0;

void vertex() {
	float t = TIME * freq + phase;
	// Rotation wobble around the sprite center (VERTEX is center-origin).
	float rot = sin(t) * 0.075 * strength;
	float c = cos(rot);
	float s = sin(rot);
	VERTEX = vec2(VERTEX.x * c - VERTEX.y * s, VERTEX.x * s + VERTEX.y * c);
	// Counter-phase squash: legs-out / legs-in scuttle.
	float squash = 1.0 + sin(t * 2.0) * 0.035 * strength;
	VERTEX.x *= squash;
	VERTEX.y /= squash;
}
