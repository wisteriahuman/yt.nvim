# yt.nvim 📺

**Neovim から YouTube を検索して、wezterm のペインに映像を流す。** URLもブラウザも要らない。

検索 → fzf で選ぶ → wezterm の右ペインに `mpv` で再生。

## 使い方

```vim
:Yt lofi hip hop      " 検索 → fzf で選択 → 再生
:Yt                   " 引数なしならプロンプトで入力
:YtStop               " 再生を止める
:YtPlayer tab         " 再生の場所/描画を切替
:YtVolume 30          " 音量(0-100)。BGMとして被せるなら低めに
```
- fzf の選択画面で **Enter = 映像再生 / Ctrl-a = 音だけ再生**（作業BGM）

## 再生方法（2軸：場所 × 描画）

**場所**（`player`）と**描画方式**（`vo`）は独立。`:YtPlayer <語>` はどちらの軸の語でも受ける。

| 場所 (`player`) | 挙動 |
|------|------|
| `pane`（既定） | 右ペインを割って再生。作業しながら観れる |
| `tab` | 新しい wezterm タブで再生（大きい） |
| `window` | mpv 通常ウィンドウ（GPU・一番滑らか＆高画質） |
| `audio` | 映像なし・音だけ |

| 描画 (`vo`)（pane/tab時） | 特徴 |
|------|------|
| `kitty`（既定） | ピクセル＝綺麗だが重い |
| `tct` | 文字セル＝粗いが軽い・滑らか（Bad Apple系） |

```vim
:YtPlayer tab     " 場所をタブに
:YtPlayer tct     " 描画をtctに（→ tab + tct も可能）
:YtSwitch tct     " 再生中のものを今の場所のままtctで再生し直す
```
組み合わせ例: `pane+kitty`(綺麗) / `pane+tct`(軽い) / `tab+tct`(大きく軽い) / `window`(最高画質)

## インストール（lazy.nvim）

```lua
{
  'wisteriahuman/yt.nvim',
  cmd = { 'Yt', 'YtPlayer', 'YtStop', 'YtSwitch', 'YtVolume' },
  keys = {
    { '<leader>Ys', function() require('yt').search() end, desc = 'YouTube検索→再生' },
    { '<leader>Yq', function() require('yt').stop() end,   desc = 'YouTube停止' },
  },
  config = function()
    require('yt').setup({ player = 'pane', pane_percent = 42 })
  end,
}
```

## 必要なもの

- `yt-dlp`（検索＋ストリーム解決）
- `mpv`（再生。`--vo=kitty` 対応ビルド）
- `wezterm` CLI（kitty graphics 対応端末）
- `fzf-lua`（無ければ `vim.ui.select` にフォールバック）

## メモ

- `--vo=kitty` 映像は端末セル解像度なので本物だが小さめ・FPSは控えめ。トーク/アニメ/解説は快適、激しい動きはカクつく。最高画質が欲しい時は `:YtPlayer window`。
- Neovim 内蔵 `:terminal` は kitty graphics 非対応なので、映像は別の wezterm ペインに出している。

## License

MIT
