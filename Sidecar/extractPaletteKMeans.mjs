// Ported verbatim from nimbus/lib/extractPaletteKMeans.ts — same seeding,
// same 22-iteration cap, same empty-cluster reseeding, so the palette matches.
function dist2(a, b) {
	const dr = a.r - b.r
	const dg = a.g - b.g
	const db = a.b - b.b
	return dr * dr + dg * dg + db * db
}

/**
 * Extrai até k cores dominantes por k-means em espaço RGB.
 * `pixels` é buffer raw row-major; `channels` 3 (RGB) ou 4 (RGBA, ignora α<128).
 */
export function extractPaletteKMeans(pixels, width, height, channels, k, maxIterations = 22) {
	const stride = channels
	const samples = []
	for (let y = 0; y < height; y += 1) {
		const row = y * width * stride
		for (let x = 0; x < width; x += 1) {
			const i = row + x * stride
			if (channels === 4) {
				const a = pixels[i + 3]
				if (a < 128) continue
			}
			samples.push({
				r: pixels[i],
				g: pixels[i + 1],
				b: pixels[i + 2],
			})
		}
	}

	if (samples.length === 0) {
		return []
	}

	let kk = Math.min(k, samples.length)
	kk = Math.max(2, kk)

	// Inicialização estável: k pontos espaçados na lista de amostras
	const centroids = []
	const step = Math.max(1, Math.floor(samples.length / kk))
	for (let i = 0; i < kk; i += 1) {
		const p = samples[Math.min(i * step, samples.length - 1)]
		centroids.push({ r: p.r, g: p.g, b: p.b })
	}

	const assignments = new Int32Array(samples.length)

	for (let iter = 0; iter < maxIterations; iter += 1) {
		let changed = false
		for (let i = 0; i < samples.length; i += 1) {
			const p = samples[i]
			let best = 0
			let bestD = dist2(p, centroids[0])
			for (let c = 1; c < kk; c += 1) {
				const d = dist2(p, centroids[c])
				if (d < bestD) {
					bestD = d
					best = c
				}
			}
			if (assignments[i] !== best) {
				assignments[i] = best
				changed = true
			}
		}

		const sumR = new Float64Array(kk)
		const sumG = new Float64Array(kk)
		const sumB = new Float64Array(kk)
		const counts = new Int32Array(kk)
		for (let i = 0; i < samples.length; i += 1) {
			const c = assignments[i]
			const p = samples[i]
			sumR[c] += p.r
			sumG[c] += p.g
			sumB[c] += p.b
			counts[c] += 1
		}

		for (let c = 0; c < kk; c += 1) {
			if (counts[c] === 0) {
				let farI = 0
				let farD = -1
				const ref = centroids[(c + 1) % kk]
				for (let i = 0; i < samples.length; i += 1) {
					const d = dist2(samples[i], ref)
					if (d > farD) {
						farD = d
						farI = i
					}
				}
				centroids[c] = { ...samples[farI] }
				changed = true
			} else {
				centroids[c] = {
					r: Math.round(sumR[c] / counts[c]),
					g: Math.round(sumG[c] / counts[c]),
					b: Math.round(sumB[c] / counts[c]),
				}
			}
		}

		if (!changed && iter > 2) break
	}

	const finalCounts = new Int32Array(kk)
	for (let i = 0; i < samples.length; i += 1) {
		finalCounts[assignments[i]] += 1
	}

	const out = []
	for (let c = 0; c < kk; c += 1) {
		if (finalCounts[c] > 0) {
			out.push({
				rgb: {
					r: Math.max(0, Math.min(255, centroids[c].r)),
					g: Math.max(0, Math.min(255, centroids[c].g)),
					b: Math.max(0, Math.min(255, centroids[c].b)),
				},
				weight: finalCounts[c],
			})
		}
	}

	out.sort((a, b) => b.weight - a.weight)
	return out
}
