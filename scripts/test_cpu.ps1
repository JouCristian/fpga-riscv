# Run from any directory: powershell -NoProfile -File scripts/test_cpu.ps1
# Testbenches use Verilog-2001 $display/$finish. Check PASS/FAIL markers as well
# as process exit codes, because $finish alone is not a failing exit in Icarus.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    New-Item -ItemType Directory -Path 'build/cpu','build/wave' -Force | Out-Null
    $rtlFiles = @(
        'rtl/cpu/cpu_top.v', 'rtl/cpu/pc.v', 'rtl/cpu/decoder.v',
        'rtl/cpu/imm_gen.v', 'rtl/cpu/regfile.v', 'rtl/cpu/alu.v',
        'rtl/cpu/branch_unit.v'
    )
    foreach ($testName in @('tb_pc', 'tb_imm_gen', 'tb_cpu')) {
        $outputFile = "build/cpu/$testName.vvp"
        $compileLog = "build/cpu/$testName.compile.log"
        $simLog = "build/cpu/$testName.log"
        & iverilog -g2001 -Wall -I rtl/cpu -s $testName -o $outputFile @rtlFiles "tb/cpu/$testName.v" 2> $compileLog
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath $compileLog | Write-Host
            throw "Icarus compilation failed: $testName"
        }
        $warnings = Get-Content -LiteralPath $compileLog -Raw
        if ($warnings) {
            Write-Host $warnings
            throw "Compilation emitted diagnostics: $testName"
        }
        $simOutput = @(& vvp $outputFile 2>&1)
        $simExitCode = $LASTEXITCODE
        $simOutput | Set-Content -LiteralPath $simLog -Encoding utf8
        $simOutput | ForEach-Object { Write-Host $_ }
        if (($simExitCode -ne 0) -or
            ($simOutput -match '\bFAIL\b') -or
            -not ($simOutput -match "^PASS ${testName}:")) {
            throw "Simulation failed: $testName"
        }
    }
    Write-Host 'PASS all CPU tests (-g2001 -Wall, no compiler diagnostics)'
} finally {
    Pop-Location
}
