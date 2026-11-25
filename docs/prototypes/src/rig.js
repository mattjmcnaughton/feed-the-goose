		// Shared by the Pay the Goose views: the scene, the goose and runner rigs, and draw(svg, pose).
		// Positions are in the scene's 340 x 176 units. Angles are degrees, clockwise.
		const DAWN = 6
		const MIDNIGHT = 24
		const DAY = 100
		const YOU_X = 231
		const GOOSE_Y = 55
		const INKC = '#1d1a2f'
		const BREAD = '#e8ae4c'
		const WHITE = '#fffdf7'
		const PUFF = [[-7, 2, 5], [-1, -5, 6], [6, -3, 5.5], [8, 4, 4.5], [0, 4, 5.5]]
		const NECK = [[64, 54], [78, 52], [92, 42], [100, 24]]
		const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v))
		const lerp = (a, b, p) => a + (b - a) * p
		// Where the goose stands for a lead: 1 is a full day's head start, 0 is its beak on your back.
		const G = (lead) => (1 - clamp(lead)) * 116
		const clock = (h) => {
			const m = Math.round(h * 60)
			if (m >= 1440) return 'midnight'
			if (m === 720) return 'noon'
			const hh = Math.floor(m / 60)
			return `${hh % 12 || 12}:${String(m % 60).padStart(2, '0')} ${hh < 12 ? 'am' : 'pm'}`
		}
		const skyStops = [
			[6, [255, 214, 165]],
			[11, [143, 211, 255]],
			[16, [150, 205, 250]],
			[18.5, [255, 160, 110]],
			[20.5, [84, 68, 158]],
			[24, [38, 33, 92]],
		]
		function skyAt(h) {
			const i = Math.max(1, skyStops.findIndex(([t]) => t >= h))
			const [t0, a] = skyStops[i - 1]
			const [t1, b] = skyStops[i]
			const k = clamp((h - t0) / (t1 - t0))
			const day = h < 19
			const p = day ? (h - DAWN) / 13 : (h - 19) / 10
			return {
				bg: `rgb(${a.map((v, j) => Math.round(lerp(v, b[j], k))).join(' ')})`,
				x: 17 + 306 * p,
				y: 130 - 92 * Math.sin(Math.PI * p),
				fill: day ? '#ffd23f' : '#fff6d6',
				stars: clamp((h - 18.5) / 2),
			}
		}
		const neckAt = (s) =>
			[0, 1].map((i) => (1 - s) ** 3 * NECK[0][i] + 3 * (1 - s) ** 2 * s * NECK[1][i] + 3 * (1 - s) * s ** 2 * NECK[2][i] + s ** 3 * NECK[3][i])
		let sceneCount = 0
		function sceneSvg(label) {
			const clip = `ptm-clip-${sceneCount++}`
			const ink = `stroke="${INKC}" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"`
			const neck = `M${NECK[0]} C${NECK[1]} ${NECK[2]} ${NECK[3]}`
			const leg = (p, x) =>
				`<g data-p="${p}"><path d="M${x} 74 V90 H${x + 10}" stroke="${INKC}" stroke-width="7.5"/><path d="M${x} 74 V90 H${x + 10}" stroke="#ff8a1f" stroke-width="3"/></g>`
			const font = `font-family="'PTM Shrik', 'Cooper Black', Georgia, serif"`
			return `<svg viewBox="0 0 340 176" role="img" aria-label="${label}">
				<defs><clipPath id="${clip}"><rect data-p="clip" x="-20" y="-14" width="40" height="28"/></clipPath></defs>
				<rect data-p="sky" width="340" height="176"/>
				<g data-p="stars" fill="#fff"><circle cx="41" cy="29" r="1.5"/><circle cx="116" cy="62" r="1.5"/><circle cx="177" cy="22" r="2"/><circle cx="241" cy="56" r="1.5"/><circle cx="306" cy="27" r="1.5"/></g>
				<circle data-p="orb" r="14.5" stroke="${INKC}" stroke-width="3"/>
				<g data-p="world">
					<rect x="-20" y="132" width="380" height="60" fill="#a9d68c"/>
					<path d="M-20 132 H360" ${ink}/>
					<path data-p="dashA" d="M-46 146 H386" stroke="${INKC}" stroke-width="3" stroke-dasharray="10 36"/>
					<path data-p="dashB" d="M-46 160 H386" stroke="${INKC}" stroke-width="3" stroke-dasharray="6 64"/>
					<g data-p="prop" ${ink}><path d="M176 132 V112 M184 132 V106" fill="none"/><rect x="173.5" y="103" width="5" height="12" rx="2.5" fill="#8a5a2b"/><rect x="181.5" y="97" width="5" height="12" rx="2.5" fill="#8a5a2b"/></g>
					<g data-p="extra"></g>
					<g data-p="goose" fill="none" stroke-linecap="round" stroke-linejoin="round">
						${leg('legA', 46)}${leg('legB', 58)}
						<g data-p="neckB"><path d="${neck}" stroke="${INKC}" stroke-width="17"/><circle data-p="bulgeB" r="12" fill="${INKC}"/></g>
						<path data-p="body" data-w="fill" d="M6 40 L26 48 C36 42 52 42 62 46 C74 50 78 62 72 70 C66 78 54 78 44 78 C26 78 12 62 6 40 Z" fill="${WHITE}" ${ink}/>
						<path data-p="wing" d="M30 54 C38 46 56 46 62 58 C52 66 38 64 30 54 Z" fill="#e6e1f0" ${ink}/>
						<g data-p="neckF">
							<path data-w="stroke" d="${neck}" stroke="${WHITE}" stroke-width="11"/>
							<circle data-p="bulgeF" data-w="fill" r="10.5" fill="${WHITE}"/>
							<g data-p="head">
								<path data-p="beakU" d="M107 16 L123 24 L108 27 Z" fill="#ff8a1f" ${ink}/>
								<path data-p="beakL" d="M107 26 L120 27.5 L105 33 Z" fill="#ff8a1f" ${ink}/>
								<circle data-w="fill" cx="100" cy="24" r="11" fill="${WHITE}" ${ink}/>
							</g>
							<path data-w="stroke" d="M94.5 33.8 L100 24" stroke="${WHITE}" stroke-width="11"/>
							<g data-p="face" stroke="${INKC}" stroke-width="2.5">
								<g data-eye="angry"><circle cx="103" cy="21" r="2.6" fill="${INKC}" stroke="none"/><path d="M97 13.5 L107 17"/></g>
								<g data-eye="happy"><path d="M99.5 22.5 q3.5 -4.5 7 0"/></g>
								<g data-eye="wide"><circle cx="103" cy="20.5" r="4.4" fill="#fff" stroke-width="2"/><circle cx="103.6" cy="20.5" r="1.7" fill="${INKC}" stroke="none"/></g>
								<g data-eye="shut"><path d="M99.5 20.5 q3.5 4 7 0"/></g>
							</g>
						</g>
					</g>
					<g data-p="loaf"><g clip-path="url(#${clip})"><path d="M-17 9 V0 C-17 -11 17 -11 17 0 V9 Z" fill="${BREAD}" ${ink}/><path d="M-8 -5 l2 5 M-1 -6 l2 5 M6 -5 l2 5" fill="none" stroke="${INKC}" stroke-width="2" stroke-linecap="round"/></g><path data-p="cut" ${ink}/></g>
					<g data-p="crust"><rect x="-7" y="-4.5" width="14" height="9" rx="4" fill="${BREAD}" stroke="${INKC}" stroke-width="2.5"/></g>
					<g data-p="crumbs" fill="${BREAD}" stroke="${INKC}" stroke-width="1.5">${'<circle r="2.4"/>'.repeat(6)}</g>
					<g data-p="you" fill="none" ${ink}>
						<g data-p="ylegA"><path d="M17 38 V55 H23"/></g>
						<g data-p="ylegB"><path d="M24 38 V55 H30"/></g>
						<path data-p="yarmsRun" d="M13 24 L4 30 M27 22 L37 18"/>
						<path data-p="yarmsUp" d="M13 22 L5 9 M27 22 L35 9"/>
						<rect x="12" y="17" width="16" height="23" rx="6" fill="#ff5a3c"/>
						<circle cx="20" cy="9" r="7.5" fill="#ffd23f"/>
					</g>
					<g data-p="puff"><g fill="${INKC}">${PUFF.map(([x, y, r]) => `<circle cx="${x}" cy="${y}" data-r="${r}"/>`).join('')}</g><g fill="${WHITE}">${PUFF.map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r}"/>`).join('')}</g></g>
					<text data-p="burst" text-anchor="middle" ${font} fill="${INKC}" stroke="${WHITE}" stroke-width="5" paint-order="stroke" stroke-linejoin="round"></text>
					<g data-p="zs" ${font} fill="#fff6d6" stroke="${INKC}" stroke-width="2.5" paint-order="stroke" stroke-linejoin="round"><text>z</text><text>z</text><text>Z</text></g>
				</g>
			</svg>`
		}
		const REST = {
			sky: skyAt(18), shake: 0, phase: 0, scroll: 0,
			gx: 0, gy: 0, size: 1, tint: WHITE, flip: 1, tilt: 0, squash: 1, belly: 1, neck: 0, head: 0, beak: 0, wing: 0, legs: 'run', eye: 'angry', bulge: -1,
			yx: 0, yy: 0, yrot: 0, ylegs: 'run', yarms: 'run',
			crust: null, loaf: null, crumbs: [], burst: null, zs: null, puff: null,
		}
		// The point `off` units in front of the goose's head centre, in scene units.
		function mouth(p, off = 20) {
			const a = ((p.neck ?? 0) * Math.PI) / 180
			const b = (((p.neck ?? 0) + (p.head ?? 0)) * Math.PI) / 180
			const lx = 64 + 36 * Math.cos(a) + 30 * Math.sin(a) + off * Math.cos(b)
			const ly = 54 + 36 * Math.sin(a) - 30 * Math.cos(a) + off * Math.sin(b) + 2
			const z = p.size ?? 1
			const fx = (p.flip ?? 1) < 0 ? 120 - lx : lx
			return { x: p.gx + 52 + (fx - 52) * z, y: GOOSE_Y + (p.gy ?? 0) + 91 + (ly - 91) * z }
		}
		function draw(svg, pose) {
			const p = { ...REST, ...pose }
			if (!svg._q) {
				svg._q = {}
				svg.querySelectorAll('[data-p]').forEach((n) => (svg._q[n.dataset.p] = n))
			}
			const q = svg._q
			const set = (n, k, v) => n.setAttribute(k, v)
			const tf = (n, s) => set(n, 'transform', s)
			const show = (n, on) => set(n, 'display', on ? 'inline' : 'none')
			const rot = (a, x, y) => `rotate(${a.toFixed(1)} ${x} ${y})`
			const at = (o) => `translate(${o.x.toFixed(1)} ${o.y.toFixed(1)}) rotate(${(o.r ?? 0).toFixed(1)}) scale(${(o.s ?? 1).toFixed(3)})`
			set(q.sky, 'fill', p.sky.bg)
			set(q.stars, 'opacity', p.sky.stars)
			set(q.orb, 'cx', p.sky.x.toFixed(1))
			set(q.orb, 'cy', p.sky.y.toFixed(1))
			set(q.orb, 'fill', p.sky.fill)
			tf(q.world, `translate(${p.shake.toFixed(1)} 0)`)
			set(q.dashA, 'stroke-dashoffset', (p.scroll % 46).toFixed(1))
			set(q.dashB, 'stroke-dashoffset', (p.scroll % 70).toFixed(1))
			tf(q.prop, `translate(${(((((80 - p.scroll) % 440) + 440) % 440) - 230).toFixed(1)} 0)`)
			if (svg._tint !== p.tint) {
				svg.querySelectorAll('[data-w]').forEach((n) => set(n, n.dataset.w, p.tint))
				svg._tint = p.tint
			}

			const run = p.legs === 'run'
			const bob = run ? -2.5 * Math.abs(Math.sin(p.phase)) : 0
			const swing = run ? 26 * Math.sin(p.phase) : 0
			tf(
				q.goose,
				`translate(${p.gx.toFixed(1)} ${(GOOSE_Y + p.gy + bob).toFixed(1)}) translate(52 91) scale(${p.size.toFixed(3)}) translate(-52 -91)${p.flip < 0 ? ' translate(120 0) scale(-1 1)' : ''} ${rot(p.tilt, 44, 88)} translate(0 91) scale(1 ${p.squash.toFixed(3)}) translate(0 -91)`,
			)
			show(q.legA, p.legs === 'run' || p.legs === 'stand')
			show(q.legB, p.legs === 'run' || p.legs === 'stand')
			tf(q.legA, rot(swing, 46, 74))
			tf(q.legB, rot(-swing, 58, 74))
			tf(q.neckB, rot(p.neck, 64, 54))
			tf(q.neckF, rot(p.neck, 64, 54))
			tf(q.head, rot(p.head, 100, 24))
			tf(q.face, rot(p.head, 100, 24))
			tf(q.beakU, rot(-0.3 * p.beak, 107, 26))
			tf(q.beakL, rot(0.7 * p.beak, 107, 26))
			tf(q.wing, rot(p.wing, 60, 57))
			tf(q.body, `translate(44 62) scale(${p.belly.toFixed(3)}) translate(-44 -62)`)
			const swallowing = p.bulge > 0 && p.bulge < 1
			show(q.bulgeB, swallowing)
			show(q.bulgeF, swallowing)
			if (swallowing) {
				const [bx, by] = neckAt(1 - p.bulge)
				for (const n of [q.bulgeB, q.bulgeF]) {
					set(n, 'cx', bx.toFixed(1))
					set(n, 'cy', by.toFixed(1))
				}
			}
			for (const n of q.face.children) show(n, n.dataset.eye === p.eye)

			const sat = p.ylegs === 'sit'
			const stride = p.ylegs === 'run' ? 30 * Math.sin(p.phase + 1) : 0
			const ybob = p.ylegs === 'run' ? -2 * Math.abs(Math.sin(p.phase + 1)) : 0
			tf(q.you, `translate(${(YOU_X + p.yx).toFixed(1)} ${(96 + p.yy + ybob).toFixed(1)}) scale(0.9) ${rot(p.yrot, 20, 30)}`)
			tf(q.ylegA, rot(sat ? -78 : stride, 17, 38))
			tf(q.ylegB, rot(sat ? -90 : -stride, 24, 38))
			show(q.yarmsRun, p.yarms !== 'up')
			show(q.yarmsUp, p.yarms === 'up')

			show(q.crust, !!p.crust)
			if (p.crust) tf(q.crust, at(p.crust))
			show(q.loaf, !!p.loaf)
			if (p.loaf) {
				const eaten = p.loaf.eaten ?? 0
				const x = -18.5 + 37 * eaten
				tf(q.loaf, at(p.loaf))
				set(q.clip, 'x', x.toFixed(1))
				show(q.cut, eaten > 0 && eaten < 1)
				set(q.cut, 'd', `M${x.toFixed(1)} ${(-8.2 * Math.sqrt(clamp(1 - (x / 17) ** 2))).toFixed(1)} V9`)
			}
			;[...q.crumbs.children].forEach((n, i) => {
				show(n, i < p.crumbs.length)
				if (i < p.crumbs.length) tf(n, `translate(${p.crumbs[i].x.toFixed(1)} ${p.crumbs[i].y.toFixed(1)})`)
			})
			show(q.burst, !!p.burst)
			if (p.burst) {
				q.burst.textContent = p.burst.text
				set(q.burst, 'font-size', p.burst.size ?? 22)
				set(q.burst, 'opacity', clamp(p.burst.o ?? 1).toFixed(2))
				tf(q.burst, at(p.burst))
			}
			show(q.zs, !!p.zs)
			if (p.zs)
				[...q.zs.children].forEach((n, i) => {
					const k = (p.zs.p + i / 3) % 1
					set(n, 'font-size', 12 + 4 * i)
					set(n, 'opacity', Math.sin(Math.PI * k).toFixed(2))
					tf(n, `translate(${(p.zs.x + 7 * i + 8 * k).toFixed(1)} ${(p.zs.y - 24 * k).toFixed(1)})`)
				})
			show(q.puff, !!p.puff)
			if (p.puff) {
				set(q.puff, 'opacity', clamp(p.puff.o ?? 1).toFixed(2))
				tf(q.puff, at(p.puff))
				// The ink ring stays about 2.5 units wide at any cloud size.
				for (const n of q.puff.firstElementChild.children) set(n, 'r', (+n.dataset.r + 2.5 / (p.puff.s ?? 1)).toFixed(2))
			}
		}
