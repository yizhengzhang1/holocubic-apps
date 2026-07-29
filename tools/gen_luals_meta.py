#!/usr/bin/env python3
"""从仓库里的实际调用点反推固件注入的全局，生成 lua-language-server 的 meta 定义。

固件（Lua 运行时 + LVGL 绑定）注入的全局不在任何 .lua 里定义，LuaLS 默认全部报
undefined-global。这里跑一遍 --check，把它诊断出的未定义全局按"被当函数调用"还是
"被当表索引"分类，生成 .luals/firmware_api.lua。

    python3 tools/gen_luals_meta.py

固件加了新绑定、或新 app 用到没见过的 API 时重跑一次。

注意 tests/ 被排除在工作区之外（.luarc.json 的 workspace.ignoreDir 同步）：主机侧测试
会把固件 API 打桩成全局（lv_obj_set_style_bg_color = function() end、httpd = {...}），
LuaLS 会把这些零参桩的形状当成该全局在整个工作区的权威签名，于是 17 个 app 里的真实
调用全被判成 redundant-parameter / undefined-field。测试靠 fengari 真跑来验证，不靠 LSP。
"""

import json
import re
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / ".luals" / "firmware_api.lua"
ALLOWLIST = REPO / ".luals" / "allowlist.txt"
DOCS = ["README_LVGL.md", "README_LUA.md", "README_HOST_ABI.md", "README.md"]
LLS = "lua-language-server"

# 标准库不该被当成固件全局重新声明——那会把真实签名盖成 fun(...):any。
LUA_STDLIB = {
    "_G", "_VERSION", "arg", "assert", "collectgarbage", "coroutine", "debug", "dofile",
    "error", "getmetatable", "io", "ipairs", "load", "loadfile", "math", "next", "os",
    "package", "pairs", "pcall", "print", "rawequal", "rawget", "rawlen", "rawset",
    "require", "select", "setmetatable", "string", "table", "tonumber", "tostring",
    "type", "utf8", "xpcall",
}


# 扫描时必须绕开已生成的 meta 文件，否则上一轮的产物会把全局都定义掉，这一轮就什么都发现不了。
SCAN_CONFIG = {
    "runtime.version": "Lua 5.4",
    "workspace.library": [],
    "workspace.ignoreDir": [
        ".luals", "**/build", "**/tests", "**/__pycache__", "mp3_player/src/legacy",
    ],
}


def run_check():
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "check.json"
        cfg = Path(tmp) / "scan.luarc.json"
        cfg.write_text(json.dumps(SCAN_CONFIG), encoding="utf-8")
        subprocess.run(
            [LLS, "--check", str(REPO), "--checklevel=Warning",
             f"--configpath={cfg}", f"--logpath={tmp}", f"--check_out_path={out}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False,
        )
        if not out.exists():
            sys.exit("lua-language-server --check 没有产出 check.json")
        return json.loads(out.read_text(encoding="utf-8"))


def collect_globals(report):
    """未定义全局 -> 出现过的调用点，调用点用来给未收录的名字做人工分辨。"""
    sites = {}
    for uri, diags in report.items():
        rel = uri.split("holocubic-apps/")[-1]
        for d in diags:
            if d.get("code") != "undefined-global":
                continue
            m = re.search(r"`([^`]+)`", d["message"])
            if m:
                sites.setdefault(m.group(1), []).append(
                    f"{rel}:{d['range']['start']['line'] + 1}"
                )
    return sites


def documented_api():
    """仓库自带的 API 文档就是权威名单。只有文档里出现过的名字才允许自动进 meta。

    提取必须窄：文档里紧挨着 ( 或 . 的标识符大多是成员方法（httpd.start）、Host ABI 的
    C 符号（calloc）甚至普通英文词，把它们当成顶层全局收进来，等于给漏写模块前缀的
    `start()` 发通行证——那这道防线就白设了。所以只认三类明确的顶层名。
    """
    docs = [(REPO / d).read_text(encoding="utf-8") for d in DOCS if (REPO / d).exists()]
    text = "\n".join(docs)
    # 围栏代码块会打乱行内反引号的配对，先按行摘掉。逐个文档处理：README_LVGL.md 的 ```
    # 行数是奇数，跨文档累积状态会让后面整篇被当成代码块吞掉。
    prose = []
    for doc in docs:
        in_fence = False
        for line in doc.splitlines():
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                continue
            if not in_fence:
                prose.append(line)
    spans = re.findall(r"`([^`\n]+)`", "\n".join(prose))
    # 任何以 .name( 形式出现过的都是成员方法，不能算顶层全局
    methods = set(re.findall(r"\.([A-Za-z_]\w*)\s*\(", text))

    # 1) 带命名空间前缀的，名字本身就无歧义
    names = set(re.findall(r"\b(lv_[a-z0-9_]+|LV_[A-Z0-9_]+|CANVAS_FMT_[A-Z0-9_]+)\b", text))
    # 2) 模块表：文档写成 wifi.connect( 时只取根名 wifi，不取 connect
    names |= {
        r for r in re.findall(r"(?<![\w.])([a-z][a-z0-9_]*)\.[A-Za-z_]\w*\s*\(", text)
        if r not in LUA_STDLIB and r != "self"
    }
    # 3) 裸函数：只认反引号里以 name( 开头的声明式写法，如 `millis() -> integer`
    names |= {
        m.group(1) for m in (re.match(r"\s*([A-Za-z_]\w*)\s*\(", s) for s in spans)
        if m and m.group(1) not in methods and m.group(1) not in LUA_STDLIB
    }
    return names


def load_allowlist():
    """文档没写、但人工确认过的真实 API。拼写错误绝不该出现在这里。"""
    if not ALLOWLIST.exists():
        return set()
    out = set()
    for line in ALLOWLIST.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            out.add(line)
    return out


def classify_source_files():
    """工作区里参与判定的 .lua（与 SCAN_CONFIG 的 ignoreDir 保持一致）。"""
    skip = (".luals", "build", "tests", "__pycache__", "legacy")
    return [p for p in REPO.rglob("*.lua") if not any(s in p.parts for s in skip)]


def classify(names):
    """按源码里的写法判定：name( 是函数，name. / name[ 是表，两者都有算表。"""
    blob = "\n".join(
        p.read_text(encoding="utf-8", errors="replace") for p in classify_source_files()
    )
    kinds = {}
    for name in names:
        as_table = re.search(rf"(?<![\w.]){re.escape(name)}\s*[.\[]", blob)
        as_call = re.search(rf"(?<![\w.]){re.escape(name)}\s*\(", blob)
        if as_table:
            kinds[name] = "table"
        elif as_call:
            kinds[name] = "function"
        else:
            kinds[name] = "value"
    return kinds


def render(names, kinds):
    lines = [
        "---@meta",
        "",
        "-- 由 tools/gen_luals_meta.py 生成，请勿手改。",
        "-- 这些全局由固件（Lua 运行时 / LVGL 绑定）注入，仓库里没有定义。",
        "-- 类型故意留得很宽：目的是消掉 undefined-global 噪音、保住拼写检查与补全，",
        "-- 不是描述真实签名。某个 API 的签名确定后，可以在这里手工细化并从生成器里排除。",
        "",
    ]
    groups = [
        ("固件模块 / 服务", lambda n: not n.startswith(("lv_", "LV_", "CANVAS_FMT_"))),
        ("LVGL 绑定函数", lambda n: n.startswith("lv_")),
        ("LVGL 常量", lambda n: n.startswith(("LV_", "CANVAS_FMT_"))),
    ]
    for title, pred in groups:
        picked = sorted(n for n in names if pred(n))
        if not picked:
            continue
        lines.append(f"-- {title}（{len(picked)} 个）")
        for n in picked:
            kind = kinds[n]
            # 模块表一律 any：仓库里没有它们的真实字段定义，用 table<string,any> 反而会
            # 和测试桩的具体形状取交集，把 tmr.alarm / httpd.stop 这类真实调用报成 undefined-field。
            lines.append("---@type fun(...):any" if kind == "function" else "---@type any")
            lines.append(f"{n} = nil")
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def main():
    report = run_check()
    sites = collect_globals(report)
    if not sites:
        sys.exit("没有发现 undefined-global —— 是不是 .luarc.json 已经把它们都盖住了？")

    known = documented_api() | load_allowlist()
    accepted = sorted(n for n in sites if n in known)
    unknown = sorted(n for n in sites if n not in known)

    kinds = classify(accepted)
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(render(accepted, kinds), encoding="utf-8")
    n_fn = sum(1 for k in kinds.values() if k == "function")
    print(f"{OUT.relative_to(REPO)}: {len(accepted)} 个全局（函数 {n_fn} / 其它 {len(accepted)-n_fn}）")

    if unknown:
        # 不写进 meta：这些名字要么是拼写错误（写进去就等于把设备上的 nil 调用藏起来），
        # 要么是文档漏了的真 API。确认属实后加进 .luals/allowlist.txt 再重跑。
        print(f"\n⚠ {len(unknown)} 个全局在文档和 allowlist 里都找不到，保留 undefined-global 诊断：")
        for n in unknown:
            print(f"  {n:34s} {sites[n][0]}" + (f" 等 {len(sites[n])} 处" if len(sites[n]) > 1 else ""))


if __name__ == "__main__":
    main()
