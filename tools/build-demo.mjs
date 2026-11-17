/**
 * 打包试玩版：把脚本内联进 HTML，得到一个单独的 demo/index.html。
 * 放到任何静态网页托管（GitHub Pages、腾讯云、阿里云等）都能直接打开，也可以直接把文件发给别人。
 * 用法：npm run build:demo
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const html = readFileSync('web/index.html', 'utf8');
const js = readFileSync('web/dist/main.js', 'utf8');
const tag = '<script src="dist/main.js"></script>';
if (!html.includes(tag)) throw new Error('index.html 里找不到脚本标签');
const out = html.replace(tag, () => `<script>\n${js.replace(/<\/script/gi, '<\\/script')}\n</script>`);
mkdirSync('demo', { recursive: true });
writeFileSync('demo/index.html', out);
console.log(`demo/index.html  ${(out.length / 1024).toFixed(1)} KB`);
