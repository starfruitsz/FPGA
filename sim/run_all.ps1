# =============================================================================
#  run_all.ps1 -- 一键编译+运行本工程的 Icarus Verilog 仿真
#  用法:  powershell -ExecutionPolicy Bypass -File .\sim\run_all.ps1
#  依赖:  Icarus Verilog (默认 C:\iverilog)，可用 -IverilogPath 指定
# =============================================================================
param(
    [string]$IverilogPath = 'C:\iverilog\bin'
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$src  = Join-Path $root 'FPGA\src'
$iv   = Join-Path $IverilogPath 'iverilog.exe'
$vvp  = Join-Path $IverilogPath 'vvp.exe'
$out  = Join-Path $here '_build'

if (-not (Test-Path $iv)) { Write-Host "找不到 iverilog: $iv" -ForegroundColor Red; exit 2 }
New-Item -ItemType Directory -Force -Path $out | Out-Null

# 用例表: 名称 / testbench / 依赖的源文件
$cases = @(
    @{ n = 'bcd';           tb = 'tb_bcd.v';           srcs = @('bcd.v') },
    @{ n = 'sine_50hz';     tb = 'tb_sine_50hz.v';     srcs = @('vga\\app\\sine_50hz.v') },
    @{ n = 'func_gen';      tb = 'tb_func_gen.v';      srcs = @('vga\app\func_gen.v','vga\app\sw_edge.v') },
    @{ n = 'uart_rx';       tb = 'tb_uart_rx.v';       srcs = @('uart_rx.v') },
    @{ n = 'cmd_chain';     tb = 'tb_cmd_chain.v';
       srcs = @('uart_rx.v','vga\app\scope_cmd.v','adc\app\adc_cmd.v') },
    @{ n = 'vga_timing';    tb = 'tb_vga_timing.v';    srcs = @('vga\hal\vga_timing.v') },
    @{ n = 'uart_tx';       tb = 'tb_uart_tx.v';       srcs = @('uart_tx.v') },
    @{ n = 'scope_capture'; tb = 'tb_scope_capture.v'; srcs = @('vga\app\scope_capture.v') },
    @{ n = 'trace_layer';   tb = 'tb_trace_layer.v';   srcs = @('vga\abs\trace_layer.v') },
    @{ n = 'scope_ui';      tb = 'tb_scope_ui.v';      srcs = @('vga\app\scope_ui.v') },
    @{ n = 'scope_app';     tb = 'tb_scope_app.v';
       srcs = @('vga\app\scope_app.v','vga\app\scope_ui.v') },
    @{ n = 'adc_ad7606_spi'; tb = 'tb_adc_ad7606_spi.v'; local = @('ad7606_model.v');
       srcs = @('adc\hal\adc_ad7606_spi.v') },
    @{ n = 'vga_test_top'; tb = 'tb_vga_test_top.v';
       srcs = @('vga\vga_test_top.v','vga\app\vga_test_app.v','vga\hal\vga_timing.v',
                'vga\hal\font_rom.v','vga\app\scope_ui.v') },
    @{ n = 'sparkroad_top'; tb = 'tb_sparkroad_top.v'; local = @('ad7606_model.v');
       srcs = @('sparkroad_scope_top.v','uart_rx.v','uart_tx.v','seg.v','bcd.v',
                'vga\vga_scope_top.v','vga\hal\vga_timing.v','vga\hal\vram_sdp.v','vga\hal\font_rom.v',
                'vga\abs\grid_layer.v','vga\abs\trace_layer.v','vga\abs\text_layer.v','vga\abs\compositor.v','vga\abs\menu_layer.v',
                'vga\app\scope_app.v','vga\app\scope_capture.v','vga\app\scope_meas.v','vga\app\scope_ui.v',
                'vga\app\scope_cmd.v','vga\app\sine_50hz.v','vga\app\func_gen.v','vga\app\sw_edge.v','vga\app\scope_autoset.v',
                'adc\adc_ad7606_top.v','adc\hal\adc_ad7606_spi.v','adc\abs\adc_cfg.v',
                'adc\abs\adc_norm.v','adc\app\adc_cmd.v') },
    @{ n = 'vga_scope_top'; tb = 'tb_vga_scope_top.v';
       srcs = @('vga\vga_scope_top.v','vga\hal\vga_timing.v','vga\hal\vram_sdp.v','vga\hal\font_rom.v',
                'vga\abs\grid_layer.v','vga\abs\trace_layer.v','vga\abs\text_layer.v','vga\abs\compositor.v','vga\abs\menu_layer.v',
                'vga\app\scope_app.v','vga\app\scope_capture.v','vga\app\scope_meas.v','vga\app\scope_ui.v',
                 'vga\app\scope_autoset.v') },
    @{ n = 'scope_trigger'; tb = 'tb_scope_trigger.v';
       srcs = @('vga\vga_scope_top.v','vga\hal\vga_timing.v','vga\hal\vram_sdp.v','vga\hal\font_rom.v',
                'vga\abs\grid_layer.v','vga\abs\trace_layer.v','vga\abs\text_layer.v','vga\abs\compositor.v','vga\abs\menu_layer.v',
                'vga\app\scope_app.v','vga\app\scope_capture.v','vga\app\scope_meas.v','vga\app\scope_ui.v',
                 'vga\app\scope_autoset.v') },
    @{ n = 'vga_scope_top_pix2'; tb = 'tb_vga_scope_top.v'; flags = @('-DPIX2');
       srcs = @('vga\vga_scope_top.v','vga\hal\vga_timing.v','vga\hal\vram_sdp.v','vga\hal\font_rom.v',
                'vga\abs\grid_layer.v','vga\abs\trace_layer.v','vga\abs\text_layer.v','vga\abs\compositor.v','vga\abs\menu_layer.v',
                'vga\app\scope_app.v','vga\app\scope_capture.v','vga\app\scope_meas.v','vga\app\scope_ui.v',
                 'vga\app\scope_autoset.v') },
    @{ n = 'adc_ad7606_top'; tb = 'tb_adc_ad7606_top.v'; local = @('ad7606_model.v');
       srcs = @('adc\adc_ad7606_top.v','adc\hal\adc_ad7606_spi.v','adc\abs\adc_cfg.v','adc\abs\adc_norm.v') }
)

$pass = 0; $fail = 0; $skip = 0
foreach ($c in $cases) {
    $tbFull = Join-Path $here $c.tb
    if (-not (Test-Path $tbFull)) { Write-Host ("  [{0}] SKIP 缺 testbench" -f $c.n) -ForegroundColor Yellow; $skip++; continue }
    $files = @($tbFull)
    if ($c.local) { foreach ($s in $c.local) { $files += (Join-Path $here $s) } }
    foreach ($s in $c.srcs) { $files += (Join-Path $src $s) }
    $vvpOut = Join-Path $out ($c.n + '.vvp')

    Write-Host ("=== {0} ===" -f $c.n) -ForegroundColor Cyan
    $flagArgs = @()
    if ($c.flags) { $flagArgs = @($c.flags) }
    $compile = & $iv -g2005 @flagArgs -o $vvpOut @files 2>&1
    if ($compile) { $compile | ForEach-Object { Write-Host ("  compile: " + $_) -ForegroundColor DarkYellow } }
    # 用退出码判定，编译告警(如 seg.v 的尺寸常量提示)不算失败
    if (($LASTEXITCODE -ne 0) -or (-not (Test-Path $vvpOut))) {
        Write-Host "  编译失败" -ForegroundColor Red; $fail++; continue }

    Push-Location $out
    $run = & $vvp -n $vvpOut 2>&1
    Pop-Location
    $run | ForEach-Object { Write-Host ("  " + $_) }

    if ($run -match '\bPASS\b') { $pass++ }
    elseif ($run -match '\bFAIL\b') { $fail++ }
    else { Write-Host "  无 PASS/FAIL 结论" -ForegroundColor Yellow; $fail++ }
    Write-Host ""
}

Write-Host ("TOTAL: PASS={0}  FAIL={1}  SKIP={2}" -f $pass, $fail, $skip) -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -ne 0) { exit 1 } else { exit 0 }