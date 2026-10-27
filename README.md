# qrvy

qrvy is a small tool for designing custom easing curves.

Place points, adjust their weights, and get a smooth cubic curve you can export as a GLSL function.

## GLSL export

Each pair of points becomes a cubic Hermite segment.

Before writing any GLSL, the generator simplifies them in a few passes:

- Merging consecutive segments that are the same polynomial.
- Compacting each polynomial by dropping zero terms, reducing the degree and factoring low powers into Horner form.
- Mirroring symmetric curves so only half is emitted.

## Try it online

- => https://bigfoot71.github.io/demos/qrvy/
