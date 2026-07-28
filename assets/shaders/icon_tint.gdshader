shader_type canvas_item;

// The icon set is flat solid-black glyphs, so a plain `modulate` multiply
// can only darken them toward black, never shift hue (black * anything =
// black). This replaces the RGB outright and keeps only the source alpha
// (the glyph's silhouette), so one icon file can be tinted any color —
// player color, muted NPC color, whatever — with no duplicate art.
uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	COLOR = vec4(tint_color.rgb, tex_color.a * tint_color.a);
}
