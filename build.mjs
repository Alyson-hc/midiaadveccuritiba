/**
 * Compila o JSX ANTES do deploy, em vez de deixar o navegador compilar.
 *
 * src/index.html e o arquivo que a gente edita: JSX solto
 * dentro de <script type="text/babel">. So que assim, a CADA carregamento, todo
 * visitante baixava o @babel/standalone (584 KB comprimidos, 2,8 MB pra
 * interpretar) e ainda compilava 534 KB de JSX na hora — 380 ms num Mac rapido,
 * varias vezes isso num celular mediano. O proprio Babel reclamava no console:
 * "exceeds the max of 500KB".
 *
 * Este script troca esse bloco pelo equivalente ja compilado e escreve o
 * index.html da RAIZ — que e o que a Hostinger publica direto do GitHub (ela
 * nao roda build). Por isso o index.html da raiz vai commitado. O importmap e o esm.sh
 * continuam iguais: aqui a gente so transforma JSX -> JS, nao empacota nada.
 *
 *   npm run build         -> index.html (minificado)
 *   npm run build:debug   -> index.html (legivel, pra depurar)
 */
import { readFile, writeFile } from 'node:fs/promises';
import { transform } from 'esbuild';

const SRC = 'src/index.html';
const OUT = 'index.html';
const BANNER = '<!-- GERADO por `npm run build` a partir de src/index.html. NAO EDITE AQUI: edite src/index.html. -->\n';

const OPEN_TAG = '<script type="text/babel" data-type="module" data-presets="react">';
const CLOSE_TAG = '</script>';
const BABEL_TAG = /[ \t]*<script src="https:\/\/unpkg\.com\/@babel\/standalone[^"]*"><\/script>\n?/;

const minify = !process.argv.includes('--no-minify');

const html = await readFile(SRC, 'utf8');

// --- localiza o bloco JSX ---------------------------------------------------
const open = html.indexOf(OPEN_TAG);
if (open === -1) {
  throw new Error(`Nao achei ${OPEN_TAG} em ${SRC}. O build precisa desse bloco exato.`);
}
const bodyStart = open + OPEN_TAG.length;
const bodyEnd = html.indexOf(CLOSE_TAG, bodyStart);
if (bodyEnd === -1) throw new Error(`O bloco JSX em ${SRC} nao foi fechado.`);
const jsx = html.slice(bodyStart, bodyEnd);

// --- JSX -> JS --------------------------------------------------------------
// jsx: 'transform' = React.createElement classico, que e o que o codigo espera
// (ele faz `import React from 'react'` e o Babel rodava com preset "react").
const { code, warnings } = await transform(jsx, {
  loader: 'jsx',
  jsx: 'transform',
  format: 'esm',
  target: 'es2020',
  minify,
  legalComments: 'none',
  sourcefile: 'app.jsx',
});

for (const w of warnings) {
  console.warn(`aviso: ${w.text}${w.location ? ` (linha ${w.location.line})` : ''}`);
}

if (code.includes(CLOSE_TAG)) {
  throw new Error('O codigo compilado contem "</script>" e quebraria o HTML inline.');
}

// --- monta o HTML de saida --------------------------------------------------
let out =
  html.slice(0, open) +
  '<script type="module">\n' + code + '\n  </script>' +
  html.slice(bodyEnd + CLOSE_TAG.length);

// o navegador nao precisa mais do compilador
if (!BABEL_TAG.test(out)) {
  throw new Error('Nao achei a tag do @babel/standalone pra remover — confira o <head>.');
}
out = out.replace(BABEL_TAG, '');
out = out.replace(/[ \t]*<!-- Babel[^\n]*\n/i, '');

out = out.replace(/^(<!DOCTYPE html>\n?)/i, `$1${BANNER}`);
if (!out.includes(BANNER)) out = BANNER + out;

await writeFile(OUT, out, 'utf8');

const kb = (s) => Math.round(Buffer.byteLength(s) / 1024);
console.log(`${OUT} pronto`);
console.log(`  JSX de entrada : ${kb(jsx)} KB`);
console.log(`  JS compilado   : ${kb(code)} KB${minify ? ' (minificado)' : ''}`);
console.log(`  HTML final     : ${kb(out)} KB`);
console.log(`  @babel/standalone removido: -584 KB de download e -380 ms de compilacao por carregamento`);
