#Requires -Version 5.1
<#
.SYNOPSIS
    Build a single-file BIG-IP topology page from a text template.

.DESCRIPTION
    Build-Topology.ps1 reads topology.conf, validates it, and writes
    BIG-IP_Topology.html: a self-contained, offline HTML page that lists every
    BIG-IP device as a link, grouped by site, cloud provider and BIG-IQ.

    Everything the script needs is embedded: the HTML boilerplate and a
    starter topology.conf. Run it with no parameters for an interactive menu,
    or use the parameters below for unattended runs.

    Files are written next to the script unless a path is given.

.PARAMETER Export
    Write the starter topology.conf and exit.

.PARAMETER Validate
    Check topology.conf and report. Writes nothing.

.PARAMETER Interactive
    Open the menu even when other parameters are supplied. The menu opens
    automatically when the script is run from a console with no parameters.

.PARAMETER InputFile
    Template to read (or to write with -Export). Default: topology.conf
    beside the script.

.PARAMETER OutputFile
    HTML file to write. Default: BIG-IP_Topology.html beside the script.

.PARAMETER Title
    Text for the browser tab and header bar. Default: BIG-IP Topology.

.PARAMETER Force
    Overwrite an existing output file.

.INPUTS
    None. Parameters only.

.OUTPUTS
    None. Exit code 0 on success, 1 on validation errors, 2 on file or
    argument errors.

.EXAMPLE
    .\Build-Topology.ps1
    Interactive menu.

.EXAMPLE
    .\Build-Topology.ps1 -Export
    Write topology.conf beside the script.

.EXAMPLE
    .\Build-Topology.ps1 -Validate
    Check topology.conf without writing.

.EXAMPLE
    .\Build-Topology.ps1 -Force -Title 'BIG-IP Links'
    Build BIG-IP_Topology.html, overwriting any existing file.

.EXAMPLE
    .\Build-Topology.ps1 -InputFile .\prod.conf -OutputFile C:\web\topo.html -Force
    Build from a named template to a named location.

.NOTES
    TEMPLATE FORMAT
    One record per line:   id|category|value[|extra[|extra]]
    Blank lines and lines beginning with # are ignored. Fields are trimmed.

      id        Block tag: lowercase letters, digits, hyphens; starts with a
                letter. The first line naming an id creates the block. Blocks
                appear on the page in order of first appearance. "all" is
                reserved.

      category  type      site | cloud | bigiq          Default site. One bigiq.
                name      Display label                 Required, once.
                enabled   true | false                  Default true.
                gtm       true | false                  Show GTM band. Default false.
                tenant    zone|device[|vcmp-host]       Site only. Zone is free text.
                host      device                        Site only. vCMP host.
                gtmdev    device                        Site or cloud. GTM device.
                device    device                        Cloud or bigiq.

      device    An FQDN, an IPv4 address, or an https:// URL. The link opens
                https://<device>. The shown name is the FQDN's first label or
                the IP. Override with   Shown Name=device

    VALIDATION
    Errors stop the build and nothing is written. Warnings are printed and the
    build continues. Every message carries the template line number.

.LINK
    https://my.f5.com
#>
[CmdletBinding(DefaultParameterSetName = 'Build')]
[OutputType([int])]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive console tool; output is for the operator, not the pipeline.')]
param(
    [Parameter(ParameterSetName = 'Export', Mandatory)]
    [switch]$Export,

    [Parameter(ParameterSetName = 'Validate', Mandatory)]
    [switch]$Validate,

    [Parameter(ParameterSetName = 'Interactive', Mandatory)]
    [switch]$Interactive,

    [Parameter(ParameterSetName = 'Build', Position = 0)]
    [Parameter(ParameterSetName = 'Export')]
    [Parameter(ParameterSetName = 'Validate')]
    [ValidateNotNullOrEmpty()]
    [string]$InputFile,

    [Parameter(ParameterSetName = 'Build', Position = 1)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputFile,

    [Parameter(ParameterSetName = 'Build')]
    [Parameter(ParameterSetName = 'Interactive')]
    [ValidateNotNullOrEmpty()]
    [string]$Title = 'BIG-IP Topology',

    [Parameter(ParameterSetName = 'Build')]
    [Parameter(ParameterSetName = 'Export')]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Version    = '1.0'
$script:ScriptDir  = Split-Path -Parent $PSCommandPath
$script:DefaultIn  = Join-Path $script:ScriptDir 'topology.conf'
$script:DefaultOut = Join-Path $script:ScriptDir 'BIG-IP_Topology.html'
$script:Utf8       = New-Object System.Text.UTF8Encoding($false)

#region Embedded assets --------------------------------------------------------

$script:HtmlHead = @'
<!DOCTYPE html>
<!--
  =============================================================================
  BIG-IP Topology  v1.0
  =============================================================================
  Single-file offline HTML page listing BIG-IP devices as links. No external
  resources, no network calls, no browser storage.

  WHERE TO EDIT
    EDIT     The data blocks under the "EDITABLE DATA" banner. Each site,
             each cloud provider, and BIG-IQ is its own <script> tag. Every
             routine change (add a site, disable a site, add a GTM, rename a
             device, change an FQDN) is made there and only there. A broken
             block removes only its own card and is reported on the page.
    EDIT     The logo <img> in <header>, marked "LOGO".
    OPTIONAL The palette at the top of <style> if colours must change.
    DO NOT   Touch anything below the "RENDER" banner in <script>, or any
             CSS below the palette. Nothing there needs to change for data
             edits.

  FILE LAYOUT
    1. <style>   Palette (editable), then layout rules (leave alone).
    2. <header>  Logo (editable), title, and two empty containers that the
                 script fills with buttons and cards.
    3. <script>  EDITABLE DATA: one tag per site / provider / BIG-IQ.
                 RENDER: a final tag that draws the page. Leave alone.

  AFTER EVERY EDIT
    Open the file in a browser and confirm:
      - The page renders and the new or changed card appears.
      - No device name is red. Red means the entry has no fqdn.
      - No band reads "Unassigned zone". That means a tenant has no zone.
      - No red notice at the top of the page. The notice means one data
        block has a syntax error (a lost comma or quote); that card is
        skipped and the notice gives the line number.
  =============================================================================
-->
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__PAGE_TITLE__</title>
<style>
/* ---------------------------------------------------------------------------
   PALETTE (editable). Values follow the F5 TMUI configuration utility.
   To change a colour, change it here. Everything below this block is
   layout and should not need editing.
   --------------------------------------------------------------------------- */
:root{
  --bg:#cfcecb;                                          /* page canvas */
  --ink:#333; --muted:#666; --line:#8f8f8f;              /* text and rules */
  --header:linear-gradient(to bottom,#777 0%,#3b3b3b 100%);     /* top bar */
  --section:linear-gradient(to bottom,#728192 0%,#525e69 100%); /* card title bars */
  --section-ink:#ffe375;                                 /* yellow card title text */
  --input:#fff; --input-line:#ccc; --focus:#6ca612;      /* filter box */
  --bad:#A3001F;                                         /* red: data error marker */
  --shadow:0 2px 6px rgba(0,0,0,.28);
  --mono:'Courier New',monospace; --sans:Roboto,'Helvetica Neue',Arial,sans-serif;
}

/* ===========================================================================
   LAYOUT RULES. No edits needed for data or colour changes.
   =========================================================================== */
/* Page frame */
*{box-sizing:border-box}
/* Always reserve the vertical scrollbar so content never shifts when it appears. */
html{overflow-y:scroll;scrollbar-gutter:stable}
body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.4 var(--sans)}
main{padding:20px 24px 40px;margin:0 auto}
/* Generic hide class used by the filter and button logic. */
.hide{display:none}

/* ---------------------------------------------------------------------------
   Header bar. Sticky. Logo, title and button grid never shrink; only the
   filter box gives up width. Below ~980px the bar scrolls sideways inside
   itself rather than widening the page.
   --------------------------------------------------------------------------- */
header{background:var(--header);color:#fff;padding:8px 24px;display:flex;align-items:flex-start;gap:16px;box-shadow:var(--shadow);position:sticky;top:0;z-index:5}
header .logo{width:50px;height:auto;display:block;flex:none;align-self:flex-start}
header h1{margin:0;font-size:20px;font-weight:normal;letter-spacing:.5px;white-space:nowrap;flex:none;align-self:flex-start;height:50px;display:flex;align-items:center}

/* Site buttons. Fixed 168x24, wrapping to as many rows as the header needs.
   Long labels shrink to fit (see the render script) rather than clipping. */
header nav{display:flex;flex-wrap:wrap;gap:6px;margin-left:12px;flex:1 1 auto;min-width:0}
header nav a{color:#fff;text-decoration:none;font:600 11px/1 var(--sans);letter-spacing:.3px;text-transform:uppercase;flex:none;width:168px;height:24px;display:inline-flex;align-items:center;justify-content:center;padding:0 6px;white-space:nowrap;overflow:hidden;border:1px solid #6e6e6d;border-radius:4px;background:linear-gradient(to bottom,#858584,#767675);box-shadow:0 1px 2px rgba(0,0,0,.3)}
header nav a:hover{background:linear-gradient(to bottom,#767675,#666665)}
header nav a.on{background:linear-gradient(to bottom,#78b81a,#5a9010);border-color:#4e7d0e;color:#fff}  /* selected: F5 green */

/* Filter box. Fixed 220px, pinned to the right edge of the header. */
#filter{flex:none;width:220px;margin-left:auto;align-self:flex-start;padding:5px 8px;font:13px var(--mono);background:var(--input);border:1px solid var(--input-line);color:var(--ink)}
#filter::placeholder{font-style:italic;color:#999}
#filter:focus{outline:none;border-color:var(--focus);box-shadow:0 0 0 3px rgba(108,166,18,.1)}

/* ---------------------------------------------------------------------------
   Card groups and grid. Sites have no heading; Cloud and BIG-IQ do.
   Columns: 4 above 1320px, 3 above 980px, 2 above 640px, else 1.
   --------------------------------------------------------------------------- */
.group{margin:0 0 22px}
.group>h2{margin:0 0 12px;font:normal 16px var(--sans);letter-spacing:.5px;color:var(--muted);text-transform:uppercase;border-bottom:1px solid var(--line);padding-bottom:4px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,var(--card,320px));gap:16px;justify-content:center}
@media (max-width:640px){.grid{grid-template-columns:1fr}}

/* ---------------------------------------------------------------------------
   Cards. One per site, cloud provider, or BIG-IQ. White body, slate title bar.
   --------------------------------------------------------------------------- */
.device{background:#fff;box-shadow:var(--shadow);border-radius:4px;overflow:hidden}
.device>h3{margin:0;padding:10px 14px;background:var(--section);color:var(--section-ink);font-size:15px;font-weight:600;display:flex;align-items:center;gap:10px}
.device>h3 .sub{color:#fff;font-weight:normal;font-size:12px;margin-left:auto;opacity:.85}  /* optional right-aligned subtitle */

/* Table rows. No header row, no zebra striping. Long names truncate with an ellipsis. */
table{border-collapse:collapse;width:100%;background:#fff;table-layout:fixed}
td{padding:5px 8px;border-bottom:1px solid #e9e8e5;vertical-align:middle;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
/* Band rows: zone / vCMP Hosts / GTM section labels within a card. */
tbody tr.zone td{background:#ebeae7;color:#333;font:600 11px var(--sans);text-transform:uppercase;letter-spacing:.4px;padding:5px 8px}
/* Device links look like plain text until hovered, as in TMUI list views. */
td a{color:#3d6382;text-decoration:none}
td a:hover{color:#28455c;text-decoration:underline}
/* Entry with no fqdn or url: rendered red and unlinked so the data error is visible. */
td .nolink{color:var(--bad)}
/* Notice shown at the top of the page when a data block failed to parse. */
.parse-error{margin:0 0 16px;padding:8px 12px;background:#FBDCE1;color:var(--bad);border:1px solid var(--bad);border-radius:4px;font:600 12px var(--sans)}
</style>
</head>
<body>
<header>
  <!-- LOGO (editable).
       The header image is embedded as base64 so the page stays a single
       offline file. To replace it:
         1. Convert a PNG to base64. In PowerShell:
              [Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\path\logo.png')) | Set-Clipboard
            (or use any base64 tool; the output is one long line of text)
         2. In the <img> tag below, select everything between the quotes
            after  src=  and paste over it:  data:image/png;base64,<pasted text>
         3. Keep the rest of the tag exactly as is. The CSS scales the image
            to 50px wide, so any reasonable PNG size works.
       Rebuilding from topology.conf writes the logo stored inside
       Build-Topology.ps1, so either re-paste after each rebuild or make the
       same edit once inside the script (search it for  img class="logo"). -->
  <img class="logo" src="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='51' height='53'%3E%3Crect width='51' height='53' rx='6' fill='%23e21d38'/%3E%3Ctext x='50%25' y='58%25' text-anchor='middle' dominant-baseline='middle' font-family='Arial' font-weight='700' font-size='26' fill='%23fff'%3EF5%3C/text%3E%3C/svg%3E" alt="F5">
  <h1>__PAGE_TITLE__</h1>
  <nav id="nav"></nav>            <!-- filled by render() -->
  <input id="filter" type="search" placeholder="filter" autocomplete="off">
</header>
<main id="main"></main>          <!-- filled by render() -->

<!--
  ============================================================================
   EDITABLE DATA
   Everything the page shows comes from the blocks below. Each site, each
   cloud provider, and BIG-IQ sits in its own <script> tag. A syntax error
   in one tag only removes that one card; every other card still renders,
   and the page shows a red notice naming the block that failed.

   The three registries SITES, CLOUD and BIGIQ are declared once, just
   below this comment, and must stay above the data blocks. Do not add a
   second declaration.

   ...........................................................................
   HOW TO
   ...........................................................................
   Enable or disable a site, cloud provider, or BIG-IQ
       Every entry carries  enabled:true  or  enabled:false  on its first
       line. Change the word. false removes the card and its button; the data
       stays in place so it can be switched back on later.

   Add a site
       Copy an entire  <script> ... </script>  site block, including both
       tags, paste it after the last site block, and change id, name and
       every hostname. Set enabled and gtmEnabled as needed. id must be
       unique, lowercase, with no spaces. Order on the page follows order
       in the file.

   Turn GTM on or off for a site or cloud provider
       Set  gtmEnabled:true  or  gtmEnabled:false  on that entry. Keep the
       gtm:[ ... ] list in place either way so the hostname is not lost.
       To add a second GTM device, add another { name, fqdn } inside gtm:[ ].
       The GTM band renders after the tenants and hosts on a site card, and
       after the device list on a cloud card.

   Add a tenant (vCMP guest)
       Add a line inside that site's guests:[ ] with name, fqdn, zone and
       host. Zones are free text; each distinct zone gets its own band, in
       the order first seen. host is the vCMP host name; not displayed, but
       the filter matches on it.

   Add or rename a vCMP host
       Edit hosts:[ ] on that site. Update the host field on its tenants so
       filtering by host name still works.

   Add a cloud provider
       Copy any  <script> ... </script>  cloud block including both tags,
       paste it after the last cloud block, change id, name and hostnames,
       and set enabled:true. To add a device to an existing provider, add a
       { name, fqdn } line inside its devices:[ ].

   Point one device at a non-standard URL
       Add  url:'https://host.example.com:8443/'  to that entry. It overrides
       the default https://<fqdn>.

   ...........................................................................
   FIELD REFERENCE
   ...........................................................................
   site block  SITES.push({ ... });  One card and one button each.
       id          Required. Unique, lowercase, no spaces.
       name        Required. Button label and card title. Buttons are 168px
                   wide; keep it short ("Site 1", "DAL", "LHR2").
       enabled     true or false. false hides the card and button. Written
                   on every entry so the on/off state is visible at a glance.
       location    Optional. Subtitle shown right-aligned in the title bar.
       guests[]    Tenants: { name, fqdn, zone, host }. Rendered under one
                   band per zone, in the order zones first appear. A guest
                   with no zone is shown under "Unassigned zone".
       hosts[]     vCMP hosts: { name, fqdn }. Rendered under "vCMP Hosts".
       gtmEnabled  true or false. Written on every site.
       gtm[]       GTM devices: { name, fqdn }.

   cloud block CLOUD.push({ ... });  One card and one button under Cloud.
       id, name, enabled as above.  devices[]  { name, fqdn }.
       gtmEnabled  true or false. Written on every provider.
       gtm[]       GTM devices: { name, fqdn }.

   bigiq block BIGIQ = { ... };  One card and one button under BIG-IQ.
       id, name, enabled as above.  devices[]  { name, fqdn }.

   Every device needs name and fqdn. Link target is https://<fqdn> unless
   url is given. A device with neither fqdn nor url is drawn red and
   unlinked.

   ...........................................................................
   SYNTAX RULES (the usual cause of a blank page)
   ...........................................................................
   - Every entry is separated from the next by a comma. No comma after the
     last entry in a list, though one there is tolerated.
   - Strings sit inside single quotes. A single quote inside a string is
     written \' .
   - Brackets and braces must balance inside each block, and each block
     must end with  });  (sites and cloud) or  };  (BIG-IQ) before its
     closing </script>.
   - A block that fails to parse is reported in red at the top of the page;
     the browser console (F12) gives the line.
  ============================================================================
-->
<script>
/* Registries. Declared once. Data blocks below push into them. */
const SITES = [], CLOUD = [];
let BIGIQ = null;
/* Records any data block that fails to parse so the page can report it. */
const PARSE_ERRORS = [];
window.addEventListener('error', e => {
  if (e.message && /Unexpected|Invalid|missing|Unterminated/i.test(e.message)) PARSE_ERRORS.push(`line ${e.lineno}: ${e.message}`);
});
</script>
'@

$script:HtmlTail = @'
<!-- ====================== RENDER (do not edit) ====================== -->
<script>
/* ============================================================================
   RENDER. Everything from here to the end of the file draws the page from
   TOPOLOGY. Do not edit for data changes; nothing below reads anything but
   the fields documented above.
   ============================================================================ */

/* HTML-escape a value before inserting it into markup. Applied to every
   data field so a stray < or " in a hostname cannot break the page. */
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

/* Link target for a device: explicit url if given, else https://<fqdn>. */
const url = d => d.url || ('https://' + d.fqdn);

/* One device row. data-k holds the lowercase text the filter matches on.
   Entries with neither fqdn nor url render as red plain text. */
function row(d) {
  return `<tr data-k="${esc([d.name, d.fqdn, d.zone, d.host].filter(Boolean).join(' ').toLowerCase())}">
    <td>${d.fqdn || d.url
      ? `<a href="${esc(url(d))}" target="_blank" title="${esc(d.fqdn || d.url)}">${esc(d.name)}</a>`
      : `<span class="nolink" title="no fqdn or url in data">${esc(d.name)}</span>`}</td></tr>`;
}

/* Section label row inside a card. */
const band = label => `<tr class="zone"><td>${esc(label)}</td></tr>`;

/* Site card body: one band per zone in first-seen order with its tenants,
   then vCMP Hosts, then GTM. */
function siteTable(s) {
  const guests = s.guests || [];
  const zones = [...new Set(guests.map(g => g.zone).filter(Boolean))];
  let body = '';
  for (const z of zones) {
    const rows = guests.filter(g => g.zone === z);
    if (rows.length) body += band(z) + rows.map(row).join('');
  }
  const unassigned = guests.filter(g => !g.zone);
  if (unassigned.length) body += band('Unassigned zone') + unassigned.map(row).join('');
  if (s.hosts?.length) body += band('vCMP Hosts') + s.hosts.map(row).join('');
  if (s.gtmEnabled === true && s.gtm?.length) body += band('GTM') + s.gtm.map(row).join('');
  return `<table><tbody>${body}</tbody></table>`;
}

/* Cloud and BIG-IQ card body: plain device list, then an optional GTM band
   (cloud only) when gtmEnabled is true and gtm[] has entries. */
function flatTable(c) {
  let body = (c.devices || []).map(row).join('');
  if (c.gtmEnabled === true && c.gtm?.length) body += band('GTM') + c.gtm.map(row).join('');
  return `<table><tbody>${body}</tbody></table>`;
}

/* Card wrapper. id must match the nav button's data-id. */
function panel(id, title, sub, inner) {
  return `<div class="device" id="${esc(id)}"><h3>${esc(title)}${sub ? `<span class="sub">${esc(sub)}</span>` : ''}</h3>${inner}</div>`;
}

/* An entry is live unless it carries enabled:false. */
const live = x => x && x.enabled !== false;

/* Assemble the data registries into one object. */
const TOPOLOGY = { get sites() { return SITES; }, get cloud() { return CLOUD; }, get bigiq() { return BIGIQ; } };

/* Build the cards and nav buttons from the data. Called once on load. */
/* Set every card to one width, sized to the longest device name or card title
   so cards are consistent and no wider than their content. Clamped 240-480px. */
function sizeCards() {
  const probe = document.createElement('span');
  probe.style.cssText = 'position:absolute;visibility:hidden;white-space:nowrap;font:13px var(--sans)';
  document.body.appendChild(probe);
  let w = 0;
  for (const el of document.querySelectorAll('td a, td .nolink')) { probe.textContent = el.textContent; w = Math.max(w, probe.offsetWidth); }
  probe.style.font = '600 15px var(--sans)';
  for (const h of document.querySelectorAll('.device > h3')) { probe.textContent = h.textContent; w = Math.max(w, probe.offsetWidth); }
  probe.remove();
  const card = Math.min(480, Math.max(240, Math.ceil(w) + 40));   /* name + cell padding */
  document.documentElement.style.setProperty('--card', card + 'px');
}

function render() {
  const t = TOPOLOGY;
  const sites = (t.sites || []).filter(live);
  const cloud = (t.cloud || []).filter(live);
  const bigiq = live(t.bigiq) ? [t.bigiq] : [];
  let html = '';
  /* Compare each data tag's header comment against what actually loaded.
     A tag whose id never reached its registry failed to parse. */
  const missing = [];
  for (const sc of document.querySelectorAll('script')) {
    const m = sc.textContent.match(/^\s*\/\* (site|cloud): ([\w-]+) \*\//);
    if (m && !(m[1] === 'site' ? SITES : CLOUD).some(x => x.id === m[2])) missing.push(`${m[1]} ${m[2]}`);
    if (/^\s*\/\* bigiq \*\//.test(sc.textContent) && !BIGIQ) missing.push('bigiq');
  }
  if (missing.length || PARSE_ERRORS.length) {
    html += `<div class="parse-error">Data block failed to load${missing.length ? ': ' + missing.map(esc).join(', ') : ''}. `
      + `That card is missing. ${PARSE_ERRORS.map(esc).join('; ')} Open the browser console (F12) for details.</div>`;
  }
  html += '<section class="group"><h2>Sites</h2><div class="grid">';
  for (const s of sites) html += panel(s.id, s.name, s.location, siteTable(s));
  html += '</div></section>';
  if (cloud.length) {
    html += '<section class="group"><h2>Cloud</h2><div class="grid">';
    for (const c of cloud) html += panel(c.id, c.name, 'Virtual Edition', flatTable(c));
    html += '</div></section>';
  }
  for (const b of bigiq) html += `<section class="group"><h2>${esc(b.name)}</h2><div class="grid">${panel(b.id, b.name, '', flatTable(b))}</div></section>`;
  if (!sites.length && !cloud.length && !bigiq.length) html += '<div class="parse-error">No data blocks loaded.</div>';
  document.getElementById('main').innerHTML = html;
  sizeCards();

  /* One button per card, plus an "All" button that clears the selection. */
  const nav = document.getElementById('nav');
  const items = [{id:'all', name:'All'}, ...sites, ...cloud, ...bigiq];
  nav.innerHTML = items.map(x => `<a href="#" data-id="${esc(x.id)}" title="${esc(x.name)}"${x.id === 'all' ? ' class="on"' : ''}>${esc(x.name)}</a>`).join('');
  /* Shrink the font on any button whose label is wider than the button, so it
     stays centered and whole rather than clipping. Floor at 8px. */
  for (const a of nav.querySelectorAll('a')) {
    let px = 11;
    while (a.scrollWidth > a.clientWidth && px > 8) { a.style.fontSize = (--px) + 'px'; }
  }
  nav.addEventListener('click', e => {
    const a = e.target.closest('a'); if (!a) return;
    e.preventDefault();            /* no anchor jump; the page must not scroll */
    const id = a.dataset.id;
    if ((e.ctrlKey || e.metaKey) && id !== 'all') { toggleSelect(id); }
    else { selectOnly(id); }
    apply();
  });
}

/* ============================================================================
   FILTER AND SELECTION
   Two inputs combine: the selected button (one card or all) and the filter
   text. apply() recomputes visibility for every row, band, card and group.
   ============================================================================ */

/* Selection is a set of data-ids. It contains 'all' (everything) or one or
   more specific card ids. Plain click selects one; Ctrl/Cmd+click toggles a
   card in or out of a multi-selection. */
const selected = new Set(['all']);
function selectOnly(id) { selected.clear(); selected.add(id); }
function toggleSelect(id) {
  selected.delete('all');
  if (selected.has(id)) { selected.delete(id); } else { selected.add(id); }
  if (selected.size === 0) selected.add('all');
}

/* Normalise for matching: lowercase, drop spaces, hyphens, underscores.
   Lets "site 2", "site2" and "Site-2" all match "site2-...". */
const norm = t => t.toLowerCase().replace(/[\s_-]+/g, '');

function apply() {
  /* Split the query into space-separated terms; a row matches if ANY term is
     found (boolean OR). Each term is normalised the same way as the keys. */
  const raw = document.getElementById('filter').value;
  const terms = raw.split(/\s+/).map(norm).filter(Boolean);
  const q = terms.length > 0;
  const showAll = selected.has('all');
  document.querySelectorAll('#nav a').forEach(a => a.classList.toggle('on', selected.has(a.dataset.id)));

  document.querySelectorAll('.device').forEach(card => {
    /* If any term matches the card title, keep every row in that card. */
    const title = norm(card.querySelector('h3').textContent);
    const titleHit = q && terms.some(t => title.includes(t));
    let any = false;
    card.querySelectorAll('tbody').forEach(tb => {
      /* Walk rows; a band is hidden when nothing beneath it survived. */
      let currentBand = null, kept = 0;
      for (const tr of tb.rows) {
        if (tr.classList.contains('zone')) {
          if (currentBand) currentBand.classList.toggle('hide', q && !titleHit && kept === 0);
          currentBand = tr; kept = 0; continue;
        }
        /* A row matches when any term is found in the row key (or the title). */
        const key = norm(tr.dataset.k || '');
        const hit = !q || titleHit || terms.some(t => key.includes(t));
        tr.classList.toggle('hide', !hit);
        if (hit) { kept++; any = true; }
      }
      if (currentBand) currentBand.classList.toggle('hide', q && !titleHit && kept === 0);
    });
    /* Card hidden if another button is selected, or the filter emptied it. */
    card.classList.toggle('hide', (!showAll && !selected.has(card.id)) || (q && !any));
  });
  /* Group headings (Cloud, BIG-IQ) hide when none of their cards are visible. */
  document.querySelectorAll('.group').forEach(g => g.classList.toggle('hide', !g.querySelector('.device:not(.hide)')));
}

const filter = document.getElementById('filter');
filter.addEventListener('input', apply);

/* Keyboard: Escape clears the filter and returns to All.
   "/" or Ctrl+K (Cmd+K) focuses the filter box. */
document.addEventListener('keydown', e => {
  /* Alt+F focuses the filter, Alt+C clears it. Escape also clears and blurs. */
  if (e.altKey && (e.key === 'f' || e.key === 'F')) { e.preventDefault(); filter.focus(); filter.select(); return; }
  if (e.altKey && (e.key === 'c' || e.key === 'C')) { e.preventDefault(); filter.value = ''; selectOnly('all'); apply(); filter.focus(); return; }
  if (e.key === 'Escape') { filter.value = ''; selectOnly('all'); apply(); filter.blur(); return; }
  if ((e.key === '/' && document.activeElement !== filter) || (e.key === 'k' && (e.ctrlKey || e.metaKey))) {
    e.preventDefault(); filter.focus(); filter.select();
  }
});

render();
</script>
</body>
</html>

'@

$script:ConfTemplate = @'
# topology.conf  -  source file for Build-Topology.ps1
#
# One fact per line:   id|category|value[|extra]
# Lines starting with # are comments. Blank lines are ignored.
#
# id        Tag for a block (site1, aws, bigiq). Lowercase letters, digits,
#           hyphens. Blocks appear on the page in order of first appearance.
#
# category  name      Label shown on the page. Required, once per block.
#           type      site | cloud | bigiq. Default site.
#           enabled   true | false. false hides the block, keeps the data.
#           gtm       true | false. Shows the GTM band.
#           tenant    Tenant (vCMP guest):  id|tenant|ZONE|fqdn[|vcmp-host]
#                     ZONE is free text; each zone gets a band on the card,
#                     in the order first seen. The optional vCMP host name is
#                     not shown but the page filter matches on it.
#           host      vCMP host                 (site only)
#           gtmdev    GTM device                (site, cloud)
#           device    Device                    (cloud, bigiq)
#
# value     FQDN, IPv4 address, or https:// URL. Link target is https://<value>.
#           Shown name is the first label of the FQDN (or the IP).
#           To show a different name:   Shown Name=fqdn
#
# Only Site 1, AWS, Azure and BIG-IQ ship enabled. Sites 2-12 and GCP/OCI are
# disabled spares: set enabled|true on the ones you use.
# Delete any block you will never use, or leave it disabled.

# ---- Site 1
site1|name|Site 1
site1|enabled|true
site1|gtm|true
site1|host|site1-vcmp01.example.com
site1|host|site1-vcmp02.example.com
site1|tenant|Zone A|site1-za-ltm01a.example.com|site1-vcmp01
site1|tenant|Zone A|site1-za-ltm01b.example.com|site1-vcmp02
site1|tenant|Zone B|site1-zb-ltm01a.example.com|site1-vcmp01
site1|tenant|Zone B|site1-zb-ltm01b.example.com|site1-vcmp02
site1|tenant|Zone C|site1-zc-ltm01a.example.com|site1-vcmp01
site1|tenant|Zone C|site1-zc-ltm01b.example.com|site1-vcmp02
site1|gtmdev|site1-gtm01.example.com

# ---- Site 2
site2|name|Site 2
site2|enabled|false
site2|gtm|true
site2|host|site2-vcmp01.example.com
site2|host|site2-vcmp02.example.com
site2|tenant|Zone A|site2-za-ltm01a.example.com|site2-vcmp01
site2|tenant|Zone A|site2-za-ltm01b.example.com|site2-vcmp02
site2|tenant|Zone B|site2-zb-ltm01a.example.com|site2-vcmp01
site2|tenant|Zone B|site2-zb-ltm01b.example.com|site2-vcmp02
site2|tenant|Zone C|site2-zc-ltm01a.example.com|site2-vcmp01
site2|tenant|Zone C|site2-zc-ltm01b.example.com|site2-vcmp02
site2|gtmdev|site2-gtm01.example.com

# ---- Site 3
site3|name|Site 3
site3|enabled|false
site3|gtm|true
site3|host|site3-vcmp01.example.com
site3|host|site3-vcmp02.example.com
site3|tenant|Zone A|site3-za-ltm01a.example.com|site3-vcmp01
site3|tenant|Zone A|site3-za-ltm01b.example.com|site3-vcmp02
site3|tenant|Zone B|site3-zb-ltm01a.example.com|site3-vcmp01
site3|tenant|Zone B|site3-zb-ltm01b.example.com|site3-vcmp02
site3|tenant|Zone C|site3-zc-ltm01a.example.com|site3-vcmp01
site3|tenant|Zone C|site3-zc-ltm01b.example.com|site3-vcmp02
site3|gtmdev|site3-gtm01.example.com

# ---- Site 4
site4|name|Site 4
site4|enabled|false
site4|gtm|false
site4|host|site4-vcmp01.example.com
site4|host|site4-vcmp02.example.com
site4|tenant|Zone A|site4-za-ltm01a.example.com|site4-vcmp01
site4|tenant|Zone A|site4-za-ltm01b.example.com|site4-vcmp02
site4|tenant|Zone B|site4-zb-ltm01a.example.com|site4-vcmp01
site4|tenant|Zone B|site4-zb-ltm01b.example.com|site4-vcmp02
site4|tenant|Zone C|site4-zc-ltm01a.example.com|site4-vcmp01
site4|tenant|Zone C|site4-zc-ltm01b.example.com|site4-vcmp02
site4|gtmdev|site4-gtm01.example.com

# ---- Site 5
site5|name|Site 5
site5|enabled|false
site5|gtm|false
site5|host|site5-vcmp01.example.com
site5|host|site5-vcmp02.example.com
site5|tenant|Zone A|site5-za-ltm01a.example.com|site5-vcmp01
site5|tenant|Zone A|site5-za-ltm01b.example.com|site5-vcmp02
site5|tenant|Zone B|site5-zb-ltm01a.example.com|site5-vcmp01
site5|tenant|Zone B|site5-zb-ltm01b.example.com|site5-vcmp02
site5|tenant|Zone C|site5-zc-ltm01a.example.com|site5-vcmp01
site5|tenant|Zone C|site5-zc-ltm01b.example.com|site5-vcmp02
site5|gtmdev|site5-gtm01.example.com

# ---- Site 6
site6|name|Site 6
site6|enabled|false
site6|gtm|false
site6|host|site6-vcmp01.example.com
site6|host|site6-vcmp02.example.com
site6|tenant|Zone A|site6-za-ltm01a.example.com|site6-vcmp01
site6|tenant|Zone A|site6-za-ltm01b.example.com|site6-vcmp02
site6|tenant|Zone B|site6-zb-ltm01a.example.com|site6-vcmp01
site6|tenant|Zone B|site6-zb-ltm01b.example.com|site6-vcmp02
site6|tenant|Zone C|site6-zc-ltm01a.example.com|site6-vcmp01
site6|tenant|Zone C|site6-zc-ltm01b.example.com|site6-vcmp02
site6|gtmdev|site6-gtm01.example.com

# ---- Site 7
site7|name|Site 7
site7|enabled|false
site7|gtm|false
site7|host|site7-vcmp01.example.com
site7|host|site7-vcmp02.example.com
site7|tenant|Zone A|site7-za-ltm01a.example.com|site7-vcmp01
site7|tenant|Zone A|site7-za-ltm01b.example.com|site7-vcmp02
site7|tenant|Zone B|site7-zb-ltm01a.example.com|site7-vcmp01
site7|tenant|Zone B|site7-zb-ltm01b.example.com|site7-vcmp02
site7|tenant|Zone C|site7-zc-ltm01a.example.com|site7-vcmp01
site7|tenant|Zone C|site7-zc-ltm01b.example.com|site7-vcmp02
site7|gtmdev|site7-gtm01.example.com

# ---- Site 8
site8|name|Site 8
site8|enabled|false
site8|gtm|false
site8|host|site8-vcmp01.example.com
site8|host|site8-vcmp02.example.com
site8|tenant|Zone A|site8-za-ltm01a.example.com|site8-vcmp01
site8|tenant|Zone A|site8-za-ltm01b.example.com|site8-vcmp02
site8|tenant|Zone B|site8-zb-ltm01a.example.com|site8-vcmp01
site8|tenant|Zone B|site8-zb-ltm01b.example.com|site8-vcmp02
site8|tenant|Zone C|site8-zc-ltm01a.example.com|site8-vcmp01
site8|tenant|Zone C|site8-zc-ltm01b.example.com|site8-vcmp02
site8|gtmdev|site8-gtm01.example.com

# ---- Site 9
site9|name|Site 9
site9|enabled|false
site9|gtm|false
site9|host|site9-vcmp01.example.com
site9|host|site9-vcmp02.example.com
site9|tenant|Zone A|site9-za-ltm01a.example.com|site9-vcmp01
site9|tenant|Zone A|site9-za-ltm01b.example.com|site9-vcmp02
site9|tenant|Zone B|site9-zb-ltm01a.example.com|site9-vcmp01
site9|tenant|Zone B|site9-zb-ltm01b.example.com|site9-vcmp02
site9|tenant|Zone C|site9-zc-ltm01a.example.com|site9-vcmp01
site9|tenant|Zone C|site9-zc-ltm01b.example.com|site9-vcmp02
site9|gtmdev|site9-gtm01.example.com

# ---- Site 10
site10|name|Site 10
site10|enabled|false
site10|gtm|false
site10|host|site10-vcmp01.example.com
site10|host|site10-vcmp02.example.com
site10|tenant|Zone A|site10-za-ltm01a.example.com|site10-vcmp01
site10|tenant|Zone A|site10-za-ltm01b.example.com|site10-vcmp02
site10|tenant|Zone B|site10-zb-ltm01a.example.com|site10-vcmp01
site10|tenant|Zone B|site10-zb-ltm01b.example.com|site10-vcmp02
site10|tenant|Zone C|site10-zc-ltm01a.example.com|site10-vcmp01
site10|tenant|Zone C|site10-zc-ltm01b.example.com|site10-vcmp02
site10|gtmdev|site10-gtm01.example.com

# ---- Site 11
site11|name|Site 11
site11|enabled|false
site11|gtm|false
site11|host|site11-vcmp01.example.com
site11|host|site11-vcmp02.example.com
site11|tenant|Zone A|site11-za-ltm01a.example.com|site11-vcmp01
site11|tenant|Zone A|site11-za-ltm01b.example.com|site11-vcmp02
site11|tenant|Zone B|site11-zb-ltm01a.example.com|site11-vcmp01
site11|tenant|Zone B|site11-zb-ltm01b.example.com|site11-vcmp02
site11|tenant|Zone C|site11-zc-ltm01a.example.com|site11-vcmp01
site11|tenant|Zone C|site11-zc-ltm01b.example.com|site11-vcmp02
site11|gtmdev|site11-gtm01.example.com

# ---- Site 12
site12|name|Site 12
site12|enabled|false
site12|gtm|false
site12|host|site12-vcmp01.example.com
site12|host|site12-vcmp02.example.com
site12|tenant|Zone A|site12-za-ltm01a.example.com|site12-vcmp01
site12|tenant|Zone A|site12-za-ltm01b.example.com|site12-vcmp02
site12|tenant|Zone B|site12-zb-ltm01a.example.com|site12-vcmp01
site12|tenant|Zone B|site12-zb-ltm01b.example.com|site12-vcmp02
site12|tenant|Zone C|site12-zc-ltm01a.example.com|site12-vcmp01
site12|tenant|Zone C|site12-zc-ltm01b.example.com|site12-vcmp02
site12|gtmdev|site12-gtm01.example.com

# ---- AWS
aws|type|cloud
aws|name|AWS
aws|enabled|true
aws|gtm|true
aws|device|aws-use1-ltm01.example.com
aws|device|aws-use1-ltm02.example.com
aws|gtmdev|aws-use1-gtm01.example.com

# ---- Azure
azure|type|cloud
azure|name|Azure
azure|enabled|true
azure|gtm|false
azure|device|az-eus-ltm01.example.com
azure|device|az-eus-ltm02.example.com
azure|gtmdev|az-eus-gtm01.example.com

# ---- GCP
gcp|type|cloud
gcp|name|GCP
gcp|enabled|false
gcp|gtm|false
gcp|device|gcp-usc1-ltm01.example.com
gcp|device|gcp-usc1-ltm02.example.com
gcp|gtmdev|gcp-usc1-gtm01.example.com

# ---- OCI
oci|type|cloud
oci|name|OCI
oci|enabled|false
oci|gtm|false
oci|device|oci-ash-ltm01.example.com
oci|device|oci-ash-ltm02.example.com
oci|gtmdev|oci-ash-gtm01.example.com

# ---- BIG-IQ
bigiq|type|bigiq
bigiq|name|BIG-IQ
bigiq|enabled|true
bigiq|device|bigiq-cm01.example.com
bigiq|device|bigiq-dcd01.example.com
bigiq|device|bigiq-dcd02.example.com
bigiq|device|bigiq-dcd03.example.com
'@

#endregion

#region Console output ---------------------------------------------------------

function Write-Line  { param([string]$Text) Write-Host "  $Text" -ForegroundColor White }
function Write-Fail  { param([string]$Text) Write-Host "  $Text" -ForegroundColor Red }
function Write-Note  { param([string]$Text) Write-Host "  $Text" -ForegroundColor Yellow }

function Read-Answer {
    param([string]$Prompt)
    Write-Host "  $Prompt" -ForegroundColor White -NoNewline
    return (Read-Host).Trim()
}

function Read-YesNo {
    param([string]$Prompt)
    while ($true) {
        switch -Regex ((Read-Answer "$Prompt (yes/no): ").ToLower()) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
            default     { Write-Line 'Enter yes or no.' }
        }
    }
}

function Confirm-Overwrite {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    return (Read-YesNo "$Path exists. Overwrite?")
}

function Write-TextFile {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        throw "Folder does not exist: $dir"
    }
    $normalised = ($Content -replace "`r?`n", [Environment]::NewLine).TrimEnd() + [Environment]::NewLine
    [System.IO.File]::WriteAllText($Path, $normalised, $script:Utf8)
}

#endregion

#region Template parsing and validation ----------------------------------------

$script:Categories = @{
    site  = @('type', 'name', 'enabled', 'gtm', 'tenant', 'host', 'gtmdev')
    cloud = @('type', 'name', 'enabled', 'gtm', 'gtmdev', 'device')
    bigiq = @('type', 'name', 'enabled', 'device')
}
$script:AllCategories = @('type', 'name', 'enabled', 'gtm', 'tenant', 'host', 'gtmdev', 'device')
$script:ReservedIds   = @('all')

$script:Rx = @{
    Id    = '^[a-z][a-z0-9-]*$'
    Fqdn  = '^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$'
    Ipv4  = '^(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$'
    Url   = '^https?://[^\s/$.?#].[^\s]*$'
    Bool  = '^(true|false)$'
}

class Note {
    [int]$Line
    [string]$Text
    Note([int]$line, [string]$text) { $this.Line = $line; $this.Text = $text }
    [string] ToString() {
        if ($this.Line -gt 0) { return ('line {0,4}: {1}' -f $this.Line, $this.Text) }
        return ('      file: {0}' -f $this.Text)
    }
}

function ConvertTo-Block {
    param([string]$Id, [int]$Line)
    return [ordered]@{
        id = $Id; type = $null; typeLine = 0; name = $null; nameLine = 0
        enabled = $true; gtm = $false; gtmLine = 0; firstLine = $Line
        guests  = [System.Collections.Generic.List[hashtable]]::new()
        hosts   = [System.Collections.Generic.List[hashtable]]::new()
        gtmdev  = [System.Collections.Generic.List[hashtable]]::new()
        devices = [System.Collections.Generic.List[hashtable]]::new()
    }
}

# Parse a device value into @{ name; fqdn; url } or return $null after recording an error.
function ConvertTo-Device {
    param([string]$Value, [int]$Line, [string]$What, [System.Collections.Generic.List[Note]]$Errors)

    $display = $null
    $target  = $Value
    if ($Value.StartsWith('=')) {
        $Errors.Add([Note]::new($Line, "${What}: empty display name before '='")); return $null
    }
    if ($Value -match '^(?<n>[^=]+)=(?<t>.+)$') {
        $display = $Matches.n.Trim()
        $target  = $Matches.t.Trim()
    }

    $dev = @{ name = $null; fqdn = $null; url = $null }
    if ($target -match '^[\d.]+$') {
        if ($target -notmatch $script:Rx.Ipv4) {
            $Errors.Add([Note]::new($Line, "${What}: '$target' is not a valid IPv4 address")); return $null
        }
        $dev.fqdn = $target
        if (-not $display) { $display = $target }
    }
    elseif ($target -match $script:Rx.Url) {
        $dev.url = $target
        if (-not $display) { $display = ([uri]$target).Host }
    }
    elseif ($target -match $script:Rx.Fqdn) {
        $dev.fqdn = $target
        if (-not $display) { $display = ($target -split '\.')[0] }
    }
    else {
        $Errors.Add([Note]::new($Line, "${What}: '$target' is not an FQDN, IPv4 address or https:// URL")); return $null
    }
    $dev.name = $display
    return $dev
}

# Parse the template. Returns @{ blocks; errors; warnings }.
function Read-Template {
    param([string]$Path)

    $errors   = [System.Collections.Generic.List[Note]]::new()
    $warnings = [System.Collections.Generic.List[Note]]::new()
    $blocks   = [ordered]@{}
    $lineNo   = 0

    foreach ($raw in [System.IO.File]::ReadAllLines($Path)) {
        $lineNo++
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }

        $f = @($line -split '\|' | ForEach-Object { $_.Trim() })
        if ($f.Count -lt 3 -or $f.Count -gt 5) {
            $errors.Add([Note]::new($lineNo, "expected 3 to 5 fields separated by |, found $($f.Count)")); continue
        }
        $id = $f[0]; $cat = $f[1].ToLower(); $val = $f[2]
        $x1 = if ($f.Count -ge 4) { $f[3] } else { $null }
        $x2 = if ($f.Count -ge 5) { $f[4] } else { $null }

        if ($id -cnotmatch $script:Rx.Id) {
            $errors.Add([Note]::new($lineNo, "id '$id' must be lowercase letters, digits and hyphens, starting with a letter")); continue
        }
        if ($id -in $script:ReservedIds) {
            $errors.Add([Note]::new($lineNo, "id '$id' is reserved")); continue
        }
        if ($cat -notin $script:AllCategories) {
            $errors.Add([Note]::new($lineNo, "unknown category '$($f[1])'; valid: $($script:AllCategories -join ' ')")); continue
        }
        if ($f.Count -eq 5 -and $cat -ne 'tenant') {
            $errors.Add([Note]::new($lineNo, "only tenant lines take 5 fields")); continue
        }

        if (-not $blocks.Contains($id)) { $blocks[$id] = ConvertTo-Block -Id $id -Line $lineNo }
        $b = $blocks[$id]

        switch ($cat) {
            'type' {
                $t = $val.ToLower()
                if ($t -notin $script:Categories.Keys) {
                    $errors.Add([Note]::new($lineNo, "type must be site, cloud or bigiq, not '$val'")); break
                }
                if ($b.typeLine) {
                    $errors.Add([Note]::new($lineNo, "type for '$id' already set on line $($b.typeLine)")); break
                }
                $b.type = $t; $b.typeLine = $lineNo
            }
            'name' {
                if ($b.nameLine) { $errors.Add([Note]::new($lineNo, "name for '$id' already set on line $($b.nameLine)")); break }
                if (-not $val)   { $errors.Add([Note]::new($lineNo, "name cannot be empty")); break }
                $b.name = $val; $b.nameLine = $lineNo
            }
            'enabled' {
                if ($val -notmatch $script:Rx.Bool) { $errors.Add([Note]::new($lineNo, "enabled must be true or false, not '$val'")); break }
                $b.enabled = ($val -eq 'true')
            }
            'gtm' {
                if ($val -notmatch $script:Rx.Bool) { $errors.Add([Note]::new($lineNo, "gtm must be true or false, not '$val'")); break }
                $b.gtm = ($val -eq 'true'); $b.gtmLine = $lineNo
            }
            'tenant' {
                if (-not $val) { $errors.Add([Note]::new($lineNo, "tenant needs a zone: id|tenant|zone|device[|vcmp-host]")); break }
                if (-not $x1)  { $errors.Add([Note]::new($lineNo, "tenant in zone '$val' needs a device: id|tenant|zone|device[|vcmp-host]")); break }
                $d = ConvertTo-Device -Value $x1 -Line $lineNo -What 'tenant' -Errors $errors
                if ($d) { $d.zone = $val; $d.host = $x2; $d.line = $lineNo; $b.guests.Add($d) }
            }
            'host' {
                $d = ConvertTo-Device -Value $val -Line $lineNo -What 'vCMP host' -Errors $errors
                if ($d) { $d.line = $lineNo; $b.hosts.Add($d) }
            }
            'gtmdev' {
                $d = ConvertTo-Device -Value $val -Line $lineNo -What 'GTM device' -Errors $errors
                if ($d) { $d.line = $lineNo; $b.gtmdev.Add($d) }
            }
            'device' {
                $d = ConvertTo-Device -Value $val -Line $lineNo -What 'device' -Errors $errors
                if ($d) { $d.line = $lineNo; $b.devices.Add($d) }
            }
        }
    }

    # Block-level checks
    $bigiqCount = 0
    $seenFqdn   = @{}
    foreach ($b in $blocks.Values) {
        if (-not $b.type) { $b.type = 'site' }
        if ($b.type -eq 'bigiq') { $bigiqCount++ }
        $ref = "block '$($b.id)' (line $($b.firstLine))"

        if (-not $b.name) { $errors.Add([Note]::new($b.firstLine, "$ref has no name line")) }

        $allowed = $script:Categories[$b.type]
        if ('tenant' -notin $allowed) { foreach ($g in $b.guests) { $errors.Add([Note]::new($g.line, "tenant lines are not valid on a $($b.type) block")) } }
        if ('host'   -notin $allowed) { foreach ($h in $b.hosts)  { $errors.Add([Note]::new($h.line, "host lines are not valid on a $($b.type) block")) } }
        if ('device' -notin $allowed) { foreach ($d in $b.devices){ $errors.Add([Note]::new($d.line, "device lines are not valid on a site block; use tenant, host or gtmdev")) } }
        if ('gtmdev' -notin $allowed) { foreach ($d in $b.gtmdev) { $errors.Add([Note]::new($d.line, "gtmdev lines are not valid on a $($b.type) block")) } }
        if ('gtm'    -notin $allowed -and $b.gtmLine) { $errors.Add([Note]::new($b.gtmLine, "gtm is not valid on a $($b.type) block")) }
        if ('gtm'    -in    $allowed -and $b.gtm -and -not $b.gtmdev.Count) { $errors.Add([Note]::new($b.gtmLine, "$ref has gtm=true but no gtmdev line")) }

        $seenName = @{}
        foreach ($d in @($b.guests) + @($b.hosts) + @($b.gtmdev) + @($b.devices)) {
            if ($seenName.ContainsKey($d.name)) { $errors.Add([Note]::new($d.line, "${ref}: display name '$($d.name)' already used on line $($seenName[$d.name])")) }
            else { $seenName[$d.name] = $d.line }
            $key = if ($d.url) { $d.url } else { $d.fqdn }
            if ($key) {
                if ($seenFqdn.ContainsKey($key)) { $warnings.Add([Note]::new($d.line, "'$key' also appears on line $($seenFqdn[$key])")) }
                else { $seenFqdn[$key] = $d.line }
            }
        }

        if ($b.type -eq 'site') {
            if (-not $b.guests.Count) { $warnings.Add([Note]::new($b.firstLine, "$ref has no tenant lines")) }
            if (-not $b.hosts.Count)  { $warnings.Add([Note]::new($b.firstLine, "$ref has no host lines")) }
            $hostNames = @($b.hosts | ForEach-Object { $_.name })
            foreach ($g in $b.guests) {
                if ($g.host -and $g.host -notin $hostNames) { $warnings.Add([Note]::new($g.line, "vCMP host '$($g.host)' is not a host line in '$($b.id)'")) }
            }
        }
        elseif (-not $b.devices.Count) { $warnings.Add([Note]::new($b.firstLine, "$ref has no device lines")) }
    }
    if ($bigiqCount -gt 1) { $errors.Add([Note]::new(0, 'more than one block has type bigiq')) }
    if (-not $blocks.Count) { $errors.Add([Note]::new(0, 'no data lines found')) }

    return @{ blocks = $blocks; errors = $errors; warnings = $warnings }
}

#endregion

#region HTML generation --------------------------------------------------------

function ConvertTo-JsString { param([string]$s) return "'" + ($s -replace '\\', '\\' -replace "'", "\'") + "'" }
function ConvertTo-JsBool   { param([bool]$v) if ($v) { 'true' } else { 'false' } }

function ConvertTo-JsDevice {
    param($d)
    $parts = @("name:$(ConvertTo-JsString $d.name)")
    if ($d.fqdn) { $parts += "fqdn:$(ConvertTo-JsString $d.fqdn)" }
    if ($d.url)  { $parts += "url:$(ConvertTo-JsString $d.url)" }
    if ($d.ContainsKey('zone') -and $d.zone) { $parts += "zone:$(ConvertTo-JsString $d.zone)" }
    if ($d.ContainsKey('host') -and $d.host) { $parts += "host:$(ConvertTo-JsString $d.host)" }
    return '{ ' + ($parts -join ', ') + ' }'
}

function ConvertTo-JsList {
    param($list, [string]$indent)
    if (-not $list.Count) { return '' }
    return ($list | ForEach-Object { "$indent$(ConvertTo-JsDevice $_)" }) -join ",`n"
}

function ConvertTo-HtmlDocument {
    param($Blocks, [string]$Title, [string]$SourceName)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append($script:HtmlHead).Append("`n")
    [void]$sb.AppendLine("<!-- Generated from $SourceName $(Get-Date -Format 'yyyy-MM-dd HH:mm') -->")

    foreach ($b in ($Blocks.Values | Where-Object { $_.type -eq 'site' })) {
        [void]$sb.AppendLine('<script>')
        [void]$sb.AppendLine("/* site: $($b.id) */")
        [void]$sb.AppendLine("SITES.push({ id:$(ConvertTo-JsString $b.id), name:$(ConvertTo-JsString $b.name), enabled:$(ConvertTo-JsBool $b.enabled),")
        [void]$sb.AppendLine('  guests:[')
        [void]$sb.AppendLine((ConvertTo-JsList $b.guests '    ') + ' ],')
        [void]$sb.AppendLine('  hosts:[')
        [void]$sb.AppendLine((ConvertTo-JsList $b.hosts '    ') + ' ],')
        [void]$sb.AppendLine("  gtmEnabled:$(ConvertTo-JsBool $b.gtm), gtm:[")
        [void]$sb.AppendLine((ConvertTo-JsList $b.gtmdev '    ') + ' ] });')
        [void]$sb.AppendLine('</script>')
    }
    foreach ($b in ($Blocks.Values | Where-Object { $_.type -eq 'cloud' })) {
        [void]$sb.AppendLine('<script>')
        [void]$sb.AppendLine("/* cloud: $($b.id) */")
        [void]$sb.AppendLine("CLOUD.push({ id:$(ConvertTo-JsString $b.id), name:$(ConvertTo-JsString $b.name), enabled:$(ConvertTo-JsBool $b.enabled), devices:[")
        [void]$sb.AppendLine((ConvertTo-JsList $b.devices '    ') + ' ],')
        [void]$sb.AppendLine("  gtmEnabled:$(ConvertTo-JsBool $b.gtm), gtm:[")
        [void]$sb.AppendLine((ConvertTo-JsList $b.gtmdev '    ') + ' ] });')
        [void]$sb.AppendLine('</script>')
    }
    foreach ($b in ($Blocks.Values | Where-Object { $_.type -eq 'bigiq' })) {
        [void]$sb.AppendLine('<script>')
        [void]$sb.AppendLine('/* bigiq */')
        [void]$sb.AppendLine("BIGIQ = { id:$(ConvertTo-JsString $b.id), name:$(ConvertTo-JsString $b.name), enabled:$(ConvertTo-JsBool $b.enabled), devices:[")
        [void]$sb.AppendLine((ConvertTo-JsList $b.devices '    ') + ' ] };')
        [void]$sb.AppendLine('</script>')
    }
    [void]$sb.Append($script:HtmlTail)

    return $sb.ToString().Replace('__PAGE_TITLE__', [System.Net.WebUtility]::HtmlEncode($Title))
}

#endregion

#region Actions (each returns an exit code) ------------------------------------

function Invoke-Export {
    param([string]$Path, [bool]$Overwrite)
    if ((Test-Path -LiteralPath $Path) -and -not $Overwrite) {
        Write-Fail "File exists: $Path  (use -Force to overwrite)"; return 2
    }
    try { Write-TextFile $Path $script:ConfTemplate } catch { Write-Fail $_.Exception.Message; return 2 }
    Write-Line "Wrote $Path"
    return 0
}

function Invoke-Build {
    param([string]$InputFile, [string]$OutputFile, [string]$Title, [bool]$Overwrite, [bool]$ValidateOnly)

    if (-not (Test-Path -LiteralPath $InputFile)) {
        Write-Fail "Not found: $InputFile"
        Write-Line 'Export the template first, then edit it.'
        return 2
    }
    $InputFile = (Resolve-Path -LiteralPath $InputFile).Path

    $r = Read-Template $InputFile
    foreach ($w in ($r.warnings | Sort-Object Line)) { Write-Note "warning $w" }
    if ($r.errors.Count) {
        Write-Fail ("{0} error(s) in {1}. Nothing written." -f $r.errors.Count, $InputFile)
        foreach ($e in ($r.errors | Sort-Object Line)) { Write-Fail "  $e" }
        return 1
    }
    if ($ValidateOnly) {
        Write-Line ("OK: {0} is valid ({1} warning(s))" -f $InputFile, $r.warnings.Count)
        return 0
    }

    if ((Test-Path -LiteralPath $OutputFile) -and -not $Overwrite) {
        Write-Fail "File exists: $OutputFile  (use -Force to overwrite)"; return 2
    }
    $html = ConvertTo-HtmlDocument -Blocks $r.blocks -Title $Title -SourceName (Split-Path -Leaf $InputFile)
    try { Write-TextFile $OutputFile $html } catch { Write-Fail $_.Exception.Message; return 2 }

    Write-Line "Wrote $OutputFile"
    return 0
}

#endregion

#region Interactive menu -------------------------------------------------------

function Show-Help {
    @'

  How to use

    1)  Export Template     Writes topology.conf next to this script.
                            The file explains its own format. Open it in a
                            text editor and replace the example entries with
                            your sites, hosts and devices.

    2)  Import Template     Checks topology.conf. Problems are listed with
                            their line numbers. Fix and import again.

    3)  Export HTML         Writes BIG-IP_Topology.html next to this script.
                            To change the header logo, open the HTML in a
                            text editor and follow the LOGO comment.

    4)  Set HTML Title      Text for the browser tab and header bar.

'@ -split "`r?`n" | ForEach-Object { Write-Host $_ -ForegroundColor White }
}

function Resolve-InputPath {
    # Menu helper: list the .conf files beside the script and let the operator
    # pick one by number, or type a filename or full path (with or without a
    # path, quoted or not). Returns a resolved path, or $null to cancel.
    # topology.conf sorts first if present; the rest follow alphabetically.
    $found = @(Get-ChildItem -LiteralPath $script:ScriptDir -Filter *.conf -File -ErrorAction SilentlyContinue |
        Sort-Object @{ Expression = { $_.Name -ne 'topology.conf' } }, Name)

    if ($found.Count) {
        Write-Line 'Templates in this folder:'
        for ($i = 0; $i -lt $found.Count; $i++) {
            Write-Host ('    {0,2}) {1}' -f ($i + 1), $found[$i].Name) -ForegroundColor White
        }
        Write-Host ''
    }
    else {
        Write-Line "No .conf files in $($script:ScriptDir)."
    }

    $answer = Read-Answer 'Number, filename or path (blank to cancel): '
    if (-not $answer) { return $null }
    $answer = $answer.Trim().Trim('"')

    # A bare number selects from the list.
    if ($answer -match '^\d+$') {
        $n = [int]$answer
        if ($n -ge 1 -and $n -le $found.Count) { return $found[$n - 1].FullName }
        Write-Fail "No item numbered $n."
        return $null
    }

    # Otherwise treat it as a filename or path. A bare filename is looked for
    # beside the script first, then as given (relative to the working folder).
    $candidates = @()
    if (-not (Split-Path -IsAbsolute $answer) -and $answer -notmatch '[\\/]') {
        $candidates += Join-Path $script:ScriptDir $answer
    }
    $candidates += $answer
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return (Resolve-Path -LiteralPath $c).Path }
    }
    Write-Fail "Not found: $answer"
    return $null
}

function Invoke-Menu {
    param([string]$Title)
    $conf    = $null      # resolved template path once imported
    $checked = $false
    while ($true) {
        Clear-Host
        Write-Host ''
        Write-Host "  BIG-IP Topology Builder  v$($script:Version)" -ForegroundColor Cyan
        Write-Host '  -----------------------------' -ForegroundColor Cyan
        Write-Host ''
        Write-Line '1)  Export Template'
        Write-Line '2)  Import Template'
        Write-Line '3)  Export HTML'
        Write-Line "4)  Set HTML Title   (Current: $Title)"
        Write-Line '5)  Help'
        Write-Line 'Q)  Quit'
        Write-Host ''
        $choice = (Read-Answer 'Select: ').ToUpper()
        Write-Host ''
        # $pause is set true by an action that leaves output worth reading
        # before the screen clears (errors, the help screen). A clean action
        # returns to the menu immediately.
        $pause = $false
        switch ($choice) {
            '1' { if (Confirm-Overwrite $script:DefaultIn) { [void](Invoke-Export -Path $script:DefaultIn -Overwrite $true); $checked = $false } }
            '2' {
                $conf = Resolve-InputPath
                if ($conf) {
                    $checked = ((Invoke-Build -InputFile $conf -OutputFile '' -Title $Title -Overwrite $true -ValidateOnly $true) -eq 0)
                    $pause = -not $checked   # pause only to show validation errors
                }
            }
            '3' {
                if (-not $checked) { Write-Line 'Import the template first (option 2).'; $pause = $true }
                elseif (Confirm-Overwrite $script:DefaultOut) {
                    if ((Invoke-Build -InputFile $conf -OutputFile $script:DefaultOut -Title $Title -Overwrite $true -ValidateOnly $false) -ne 0) { $pause = $true }
                }
            }
            '4' {
                $v = Read-Answer 'New title: '
                if ($v) { $Title = $v } else { Write-Line 'Title unchanged.' }
            }
            '5' { Show-Help; $pause = $true }
            'Q' { return 0 }
            default { Write-Line 'Choose 1-5 or Q.'; $pause = $true }
        }
        if ($pause) {
            Write-Host ''
            [void](Read-Answer 'Press Enter to continue ')
        }
    }
}

#endregion

#region Entry point ------------------------------------------------------------

$console = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
$noArgs  = ($PSBoundParameters.Count -eq 0)

if ($Interactive -or ($noArgs -and $console)) {
    exit (Invoke-Menu -Title $Title)
}

if (-not $InputFile)  { $InputFile  = $script:DefaultIn }
if (-not $OutputFile) { $OutputFile = $script:DefaultOut }

switch ($PSCmdlet.ParameterSetName) {
    'Export'   { exit (Invoke-Export -Path $InputFile -Overwrite ([bool]$Force)) }
    'Validate' { exit (Invoke-Build -InputFile $InputFile -OutputFile '' -Title $Title -Overwrite $true -ValidateOnly $true) }
    default    { exit (Invoke-Build -InputFile $InputFile -OutputFile $OutputFile -Title $Title -Overwrite ([bool]$Force) -ValidateOnly $false) }
}

#endregion
