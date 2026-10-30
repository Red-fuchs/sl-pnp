import Foundation
import MLX
import MLXNN

/// Activation/param dtype: fp16 by default (bf16 is software-emulated on M1/M2 GPUs, ~1.4-1.7x slower); SL_DTYPE=bf16 keeps the checkpoint dtype.
/// Every floating param is cast (mixing bf16 activations with fp16 params promotes to fp32, mlx-swift #420).
func slDtype() -> DType? {
  switch ProcessInfo.processInfo.environment["SL_DTYPE"]?.lowercased() {
  case "bf16", "bfloat16": return nil
  case "fp32", "float32": return .float32
  default: return .float16
  }
}

func castParameters(_ m: Module, to t: DType) {
  m.update(parameters: m.mapParameters { $0.dtype.isFloatingPoint && $0.dtype != t ? $0.asType(t) : $0 })
  eval(m)
}
