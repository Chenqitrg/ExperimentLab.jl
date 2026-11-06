# Shared setup for VS Code file/selection execution and ordinary include.
# Keep the examples environment active so subsequent REPL commands use it too.
import Pkg
Pkg.activate(@__DIR__; io=devnull)
Pkg.instantiate(; allow_autoprecomp=false)
