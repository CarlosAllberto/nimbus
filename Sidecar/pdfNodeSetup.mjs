import './pdfNodeSetup.mjs'

const g = globalThis

if (typeof g.DOMMatrix === 'undefined') {
  const DOMMatrixImpl = class {
    a = 1
    b = 0
    c = 0
    d = 1
    e = 0
    f = 0
    m11 = 1
    m12 = 0
    m13 = 0
    m14 = 0
    m21 = 0
    m22 = 1
    m23 = 0
    m24 = 0
    m31 = 0
    m32 = 0
    m33 = 1
    m34 = 0
    m41 = 0
    m42 = 0
    m43 = 0
    m44 = 1
    is2D = true
    isIdentity = true

    constructor(init) {
      if (Array.isArray(init) && init.length >= 6) {
        this.set2d(init[0], init[1], init[2], init[3], init[4], init[5])
      }
    }

    set2d(a, b, c, d, e, f) {
      this.a = this.m11 = a
      this.b = this.m12 = b
      this.c = this.m21 = c
      this.d = this.m22 = d
      this.e = this.m41 = e
      this.f = this.m42 = f
      this.isIdentity = a === 1 && b === 0 && c === 0 && d === 1 && e === 0 && f === 0
      return this
    }

    multiplySelf() {
      return this
    }
    preMultiplySelf() {
      return this
    }
    translateSelf() {
      return this
    }
    scaleSelf() {
      return this
    }
    rotateSelf() {
      return this
    }
    invertSelf() {
      return this
    }

    static fromMatrix() {
      return new DOMMatrixImpl()
    }
  }
  g.DOMMatrix = DOMMatrixImpl
}

if (typeof g.DOMPoint === 'undefined') {
  const DOMPointImpl = class {
    x = 0
    y = 0
    z = 0
    w = 1
    constructor(x = 0, y = 0, z = 0, w = 1) {
      this.x = x
      this.y = y
      this.z = z
      this.w = w
    }
  }
  g.DOMPoint = DOMPointImpl
}
