# =============================================================================
#  run_all.ps1 -- 一键编译+运行本工程的 Icarus Verilog 仿真
#  用法:  powershell -ExecutionPolicy Bypass -File .\sim\run_all.ps1
#  依赖:  Icarus Verilog (默认 C:\iverilog)，可用 -IverilogPath 指定
#
#  注意: 本文件必须保存为 "UTF-8 带 BOM"。Windows PowerShell 5.1 读取无 BOM 的
#        UTF-8 文件时按 ANSI(GBK) 解码，中文注释里的多字节序列会吞掉换行，
#        把下一行代码并进注释里 —— $cases 数组的最后一个元素就是这样被吃掉的，
#        表现为 "缺少表达式" 的语法错误，脚本根本跑不起来。
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

# -----------------------------------------------------------------------------
# 用例表
#   n     = 用例名（也是 _build 下的产物名）
#   tb    = sim 目录下的 testbench
#   srcs  = 相对 FPGA\src 的源文件（可跨多行写，每个字符串自带引号+逗号）
#   local = 相对 sim 目录的本地模型（可选）
#   flags = 额外编译选项（可选）
# 每个 @{} 之间用逗号分隔；最后一项后面不要写逗号。
# -----------------------------------------------------------------------------
$cases = @(
    @{ n = 'bcd';            tb = 'tb_bcd.v';            srcs = @('bcd.v') },
    @{ n = 'sine_50hz';      tb = 'tb_sine_50hz.v';      srcs = @('vga\app\sine_50hz.v') },
    @{ n = 'func_gen';       tb = 'tb_func_gen.v';       srcs = @('vga\app\func_gen.v', 'vga\app\sw_edge.v') },
    @{ n = 'uart_rx';        tb = 'tb_uart_rx.v';        srcs = @('uart_rx.v') },
    @{ n = 'uart_tx';        tb = 'tb_uart_tx.v';        srcs = @('uart_tx.v') },
    @{ n = 'vga_timing';     tb = 'tb_vga_timing.v';     srcs = @('vga\hal\vga_timing.v') },
    @{ n = 'trace_layer';    tb = 'tb_trace_layer.v';    srcs = @('vga\abs\trace_layer.v') },
    @{ n = 'scope_ui';       tb = 'tb_scope_ui.v';       srcs = @('vga\app\scope_ui.v') },
    @{ n = 'scope_capture';  tb = 'tb_scope_capture.v';  srcs = @('vga\app\scope_capture.v') },
    @{ n = 'cmd_chain';      tb = 'tb_cmd_chain.v';
       srcs = @('uart_rx.v', 'vga\app\scope_cmd.v', 'adc\app\adc_cmd.v') },
    @{ n = 'scope_app';      tb = 'tb_scope_app.v';
       srcs = @('vga\app\scope_app.v', 'vga\app\scope_ui.v') },
    @{ n = 'adc_ad7606_spi'; tb = 'tb_adc_ad7606_spi.v'; local = @('ad7606_model.v');
       srcs = @('adc\hal\adc_ad7606_spi.v') },
    @{ n = 'adc_ad7606_top'; tb = 'tb_adc_ad7606_top.v'; local = @('ad7606_model.v');
       srcs = @('adc\adc_ad7606_top.v', 'adc\hal\adc_ad7606_spi.v',
                'adc\abs\adc_cfg.v',  'adc\abs\adc_norm.v') },
    @{ n = 'vga_test_top';   tb = 'tb_vga_test_top.v';
       srcs = @('vga\vga_test_top.v', 'vga\app\vga_test_app.v', 'vga\hal\vga_timing.v',
                'vga\hal\font_rom.v', 'vga\app\scope_ui.v') },
    @{ n = 'vga_scope_top';  tb = 'tb_vga_scope_top.v';
       srcs = @('vga\vga_scope_top.v', 'vga\hal\vga_timing.v', 'vga\hal\vram_sdp.v', 'vga\hal\font_rom.v',
                'vga\abs\grid_layer.v', 'vga\abs\trace_layer.v', 'vga\abs\text_layer.v',
                'vga\abs\compositor.v', 'vga\abs\menu_layer.v',
                'vga\app\scope_app.v', 'vga\app\scope_capture.v', 'vga\app\scope_meas.v',
                'vga\app\scope_ui.v',  'vga\app\scope_autoset.v') },
    @{ n = 'vga_scope_top_pix2'; tb = 'tb_vga_scope_top.v'; flags = @('-DPIX2');
       srcs = @('vga\vga_scope_top.v', 'vga\hal\vga_timing.v', 'vga\hal\vram_sdp.v', 'vga\hal\font_rom.v',
                'vga\abs\grid_layer.v', 'vga\abs\trace_layer.v', 'vga\abs\text_layer.v',
                'vga\abs\compositor.v', 'vga\abs\menu_layer.v',
                'vga\app\scope_app.v', 'vga\app\scope_capture.v', 'vga\app\scope_meas.v',
                'vga\app\scope_ui.v',  'vga\app\scope_autoset.v') },
    @{ n = 'scope_trigger';  tb = 'tb_scope_trigger.v';
       srcs = @('vga\vga_scope_top.v', 'vga\hal\vga_timing.v', 'vga\hal\vram_sdp.v', 'vga\hal\font_rom.v',
                'vga\abs\grid_layer.v', 'vga\abs\trace_layer.v', 'vga\abs\text_layer.v',
                'vga\abs\compositor.v', 'vga\abs\menu_layer.v',
                'vga\app\scope_app.v', 'vga\app\scope_capture.v', 'vga\app\scope_meas.v',
                'vga\app\scope_ui.v',  'vga\app\scope_autoset.v') },
    # 并口 AD/DA 模块（24 脚）驱动: ADCLK/DACLK 8 分频、AD 反相沿采样 + 两拍同步、DA 上升沿锁存
    @{ n = 'ad_da_par';      tb = 'tb_ad_da_par.v';      srcs = @('ad_da_par.v') },
    # ESO(ADRC) 观测器: sys_clk 域 + 每采样一次使能（en=0 时状态保持）
    @{ n = 'eso';            tb = 'tb_eso.v';            srcs = @('eso.v') },
    # 整机: ADC + 并口 AD/DA + ADRC + VGA + 数码管 + 串口
    @{ n = 'sparkroad_top';  tb = 'tb_sparkroad_top.v'; local = @('ad7606_model.v');
       srcs = @('sparkroad_scope_top.v', 'ad_da_par.v', 'eso.v',
                'uart_rx.v', 'uart_tx.v', 'seg.v', 'bcd.v',
                'vga\vga_scope_top.v', 'vga\hal\vga_timing.v', 'vga\hal\vram_sdp.v', 'vga\hal\font_rom.v',
                'vga\abs\grid_layer.v', 'vga\abs\trace_layer.v', 'vga\abs\text_layer.v',
                'vga\abs\compositor.v', 'vga\abs\menu_layer.v',
                'vga\app\scope_app.v', 'vga\app\scope_capture.v', 'vga\app\scope_meas.v',
                'vga\app\scope_ui.v',  'vga\app\scope_cmd.v',  'vga\app\sine_50hz.v',
                'vga\app\func_gen.v',  'vga\app\sw_edge.v',   'vga\app\scope_autoset.v',
                'adc\adc_ad7606_top.v', 'adc\hal\adc_ad7606_spi.v', 'adc\abs\adc_cfg.v',
                'adc\abs\adc_norm.v',  'adc\app\adc_cmd.v') }
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
