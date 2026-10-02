/* lens.c -- the per-pixel work of example/Lens.ahk, compiled to machine code
   and embedded there as hex (see "build" in Lens.ahk). Freestanding: no
   library calls, no constants in memory -- every number it needs is passed
   in P[] -- so the bytes run from wherever they are copied.

   P[0] radius   P[1] strength (+ magnifies, - shrinks)   P[2] colour split
   P[3] 1.0      P[4] 0.5      P[5] 255.0                   P[6] 0.0        */

typedef unsigned int u32;
typedef unsigned char u8;

/* where each pixel of the lens looks in the picture behind it, per channel,
   and how much of the lens covers it (the anti-aliased circle) */
void lens_build(int D, const double *P, int *mR, int *mG, int *mB, u8 *alpha)
{
    double R = P[0], s = P[1], ca0 = P[2], one = P[3], half = P[4], full = P[5], zero = P[6];
    for (int y = 0; y < D; y++)
        for (int x = 0; x < D; x++) {
            int i = y * D + x;
            double dx = ((double)x + half - R) / R, dy = ((double)y + half - R) / R;
            double r2 = dx * dx + dy * dy;
            double d = __builtin_sqrt(r2) * R;                      /* px from the centre */
            double cover = R - d + half;                            /* 1 px soft edge */
            if (cover <= zero) { alpha[i] = 0; mR[i] = mG[i] = mB[i] = i; continue; }
            if (cover > one) cover = one;
            alpha[i] = (u8)(cover * full);
            double k = one - r2; if (k < zero) k = zero;
            double f = one - s * k;                                 /* the lens: middle magnified */
            double r6 = r2 * r2 * r2, ca = ca0 * r6;                /* colours split at the rim */
            double fs[3] = { f * (one + ca), f, f * (one - ca) };
            int *maps[3] = { mR, mG, mB };
            for (int c = 0; c < 3; c++) {
                int sx = (int)(R + dx * fs[c] * R), sy = (int)(R + dy * fs[c] * R);
                if (sx < 0) sx = 0; if (sx >= D) sx = D - 1;
                if (sy < 0) sy = 0; if (sy >= D) sy = D - 1;
                maps[c][i] = sy * D + sx;
            }
        }
}

/* one frame: dst (premultiplied ARGB, for UpdateLayeredWindow) = the picture
   behind, bent through the maps, under the glass overlay (premultiplied) */
void lens_frame(const u32 *src, u32 *dst, const int *mR, const int *mG, const int *mB,
                const u8 *alpha, const u32 *over, int n)
{
    for (int i = 0; i < n; i++) {
        u32 a = alpha[i];
        if (!a) { dst[i] = 0; continue; }
        u32 r = (src[mR[i]] >> 16) & 255, g = (src[mG[i]] >> 8) & 255, b = src[mB[i]] & 255;
        if (a != 255) { r = r * a / 255; g = g * a / 255; b = b * a / 255; }
        u32 o = over[i], oa = o >> 24;
        if (oa) {
            u32 inv = 255 - oa;
            r = ((o >> 16) & 255) + r * inv / 255;
            g = ((o >> 8) & 255) + g * inv / 255;
            b = (o & 255) + b * inv / 255;
            a = oa + a * inv / 255;
        }
        dst[i] = (a << 24) | (r << 16) | (g << 8) | b;
    }
}
