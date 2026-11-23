#!/usr/bin/env python3
"""
=============================================================================
  CORDIC Reference Model & LUT Generator
  32-bit Q2.29 | 20 iterations | Python floating-point simulation
=============================================================================
  Chuc nang:
    1. In bang LUT atan(2^-i) dang hex Q2.29 (dung cho Verilog)
    2. In cac hang so An, 1/An, pi/2, pi dang hex Q2.29
    3. Mo phong CORDIC ROTATION   -> kiem tra cos/sin
    4. Mo phong CORDIC VECTORING  -> kiem tra atan2, magnitude
    5. In ket qua sai so so voi math.cos / math.sin / math.atan2

  Cach chay:
    python cordic_ref.py

  Ket qua mong doi: tat ca test PASS, sai so < 1e-4

  [FIX] Hang so pi/2 hex duoc dong bo voi cordic_top.v: 32'h3243F6A9
        (gia tri chinh xac: round(pi/2 * 2^29) = 0x3243F6A9)
=============================================================================
"""

import math

# ─── Cau hinh ────────────────────────────────────────────────────────────────
N    = 32        # so bit
FRAC = 29        # so bit phan (Q2.29)
ITER = 20        # so vong lap CORDIC
SCALE = 2 ** FRAC  # = 536870912

TOL_ROT = 1e-4   # nguong sai so ROTATION
TOL_VEC = 1e-4   # nguong sai so VECTORING

# ─── Ham chuyen doi Q2.29 ─────────────────────────────────────────────────────
def to_q29(x: float) -> int:
    """Chuyen float -> so nguyen Q2.29 (unsigned 32-bit hex)."""
    return round(x * SCALE) & 0xFFFFFFFF

def from_q29(v: int) -> float:
    """Chuyen so nguyen Q2.29 (signed) -> float."""
    if v >= 2 ** (N - 1):
        v -= 2 ** N
    return v / SCALE

# ─── Bang LUT atan(2^-i) ──────────────────────────────────────────────────────
atan_lut = [math.atan(2 ** (-i)) for i in range(ITER)]

# ─── Tinh hang so CORDIC ─────────────────────────────────────────────────────
An    = math.prod(math.cos(math.atan(2 ** (-i))) for i in range(ITER))
inv_An = 1.0 / An

# =============================================================================
# Phan 1: In bang LUT va hang so cho Verilog
# =============================================================================
SEP = "=" * 62

print(SEP)
print(f"  CORDIC {N}-bit Q2.29  |  ITER = {ITER}")
print(SEP)

print(f"\n-- Bang LUT atan(2^-i) (dat vao cordic_core.v) --")
print(f"// localparam dang Verilog:")
for i, a in enumerate(atan_lut):
    q     = to_q29(a)
    comma = "," if i < ITER - 1 else " "
    print(f"    32'h{q:08X}{comma}  // atan(2^-{i:2d}) = {a:.10f} rad")

# [FIX] Pi/2 hex dong bo: round(pi/2 * 2^29) = 0x3243F6A9
pi_half_hex = to_q29(math.pi / 2)
pi_hex      = to_q29(math.pi)
neg_pi_half_hex = to_q29(-math.pi / 2) & 0xFFFFFFFF

print(f"\n-- Hang so chinh (Q2.29) --")
print(f"  An    = {An:.10f}  ->  32'h{to_q29(An):08X}")
print(f"  1/An  = {inv_An:.10f}  ->  32'h{to_q29(inv_An):08X}")
print(f"  pi/2  = {math.pi/2:.10f}  ->  32'h{pi_half_hex:08X}   <- dung voi cordic_top.v")
print(f"  -pi/2 = {-math.pi/2:.10f} ->  32'h{neg_pi_half_hex:08X}  (NEG_PI_HALF)")
print(f"  pi    = {math.pi:.10f}  ->  32'h{pi_hex:08X}")

# =============================================================================
# Phan 2: Ham mo phong CORDIC (float, mirrors RTL logic)
# =============================================================================

def cordic_rotation(theta: float):
    """
    Mo phong CORDIC ROTATION.
    Mirrors cordic_top.v: x_init = An (or -An for quadrant 2/3).
    Tra ve (cos(theta), sin(theta)).
    """
    # Quadrant fold (giong cordic_top.v)
    if theta > math.pi / 2:
        x_init = -An
        theta  = theta - math.pi
    elif theta < -math.pi / 2:
        x_init = -An
        theta  = theta + math.pi
    else:
        x_init = An

    x, y, z = x_init, 0.0, theta
    for i in range(ITER):
        sigma = 1 if z >= 0 else -1
        # Ghi chu: Python tuple unpacking evaluate ve phai truoc -> dung
        x, y, z = (x - sigma * y * 2**(-i),
                   y + sigma * x * 2**(-i),
                   z - sigma * atan_lut[i])
    return x, y   # = cos(theta), sin(theta)


def cordic_vectoring(xi: float, yi: float):
    """
    Mo phong CORDIC VECTORING.
    Tra ve (magnitude * (1/An), atan2(yi, xi)).
    De lay true magnitude: nhan x_out voi An.
    """
    x, y, z = xi, yi, 0.0
    for i in range(ITER):
        sigma = -1 if y >= 0 else 1
        x, y, z = (x - sigma * y * 2**(-i),
                   y + sigma * x * 2**(-i),
                   z - sigma * atan_lut[i])
    return x, z   # x = hypot(xi,yi)*(1/An),  z = atan2(yi,xi)

# =============================================================================
# Phan 3: Kiem tra ROTATION
# =============================================================================
print(f"\n{SEP}")
print("  ROTATION MODE  (cos / sin)")
print(SEP)

angles = [
    0,
    math.pi / 6,    #  30 deg
    math.pi / 4,    #  45 deg
    math.pi / 3,    #  60 deg
    math.pi / 2,    #  90 deg
    -math.pi / 4,   # -45 deg
    3 * math.pi / 4,# 135 deg  (quadrant fold test)
    -math.pi / 2,   # -90 deg
    0.1,
    1.0,
    -1.0,
]

max_err_rot = 0.0
all_pass_rot = True
for theta in angles:
    cx, sy   = cordic_rotation(theta)
    ref_cos  = math.cos(theta)
    ref_sin  = math.sin(theta)
    ec       = abs(cx - ref_cos)
    es       = abs(sy - ref_sin)
    max_err_rot = max(max_err_rot, ec, es)
    ok = "PASS" if max(ec, es) < TOL_ROT else "FAIL"
    if ok == "FAIL":
        all_pass_rot = False
    print(f"  [{ok}] theta={theta:+.4f} rad  "
          f"cos={cx:+.6f}(err={ec:.1e})  "
          f"sin={sy:+.6f}(err={es:.1e})")

print(f"\n  Max error = {max_err_rot:.2e}  "
      f"(~ 2^{math.log2(max_err_rot + 1e-99):.1f} bits)")

# =============================================================================
# Phan 4: Kiem tra VECTORING
# =============================================================================
print(f"\n{SEP}")
print("  VECTORING MODE  (atan2 / magnitude)")
print(SEP)

vectors = [
    (1.0, 0.0),
    (1.0, 1.0),
    (0.0, 1.0),
    (0.6, 0.8),                          # 3-4-5 triangle
    (0.3, 0.4),                          # scaled 3-4-5
    (math.sqrt(3) / 2, 0.5),             # 30 deg
    (0.5, math.sqrt(3) / 2),             # 60 deg
]

max_err_ang = 0.0
max_err_mag = 0.0
all_pass_vec = True
for xi, yi in vectors:
    mag_scaled, ang = cordic_vectoring(xi, yi)
    mag        = mag_scaled * An           # true magnitude (remove CORDIC gain)
    ref_ang    = math.atan2(yi, xi)
    ref_mag    = math.hypot(xi, yi)
    ea         = abs(ang - ref_ang)
    em         = abs(mag - ref_mag)
    max_err_ang = max(max_err_ang, ea)
    max_err_mag = max(max_err_mag, em)
    ok = "PASS" if max(ea, em) < TOL_VEC else "FAIL"
    if ok == "FAIL":
        all_pass_vec = False
    print(f"  [{ok}] ({xi:.4f}, {yi:.4f})  "
          f"angle={ang:+.6f}(err={ea:.1e})  "
          f"mag={mag:.6f}(err={em:.1e})")

print(f"\n  Max angle error = {max_err_ang:.2e}  "
      f"(~ 2^{math.log2(max_err_ang + 1e-99):.1f} bits)")
print(f"  Max mag   error = {max_err_mag:.2e}  "
      f"(~ 2^{math.log2(max_err_mag + 1e-99):.1f} bits)")

# =============================================================================
# Phan 5: Tong ket
# =============================================================================
print(f"\n{SEP}")
rot_status = "PASS" if all_pass_rot else "FAIL"
vec_status = "PASS" if all_pass_vec else "FAIL"
print(f"  ROTATION  : {rot_status}")
print(f"  VECTORING : {vec_status}")
if all_pass_rot and all_pass_vec:
    print("  Ket qua: Tat ca test PASS - Mo hinh CORDIC chinh xac.")
else:
    print("  Ket qua: Co test FAIL - Kiem tra lai tham so.")
print(SEP)
