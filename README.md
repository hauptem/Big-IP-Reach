# F5-BIG-IP-Reach

An offline, single-file HTML directory for reaching F5 BIG-IP management interfaces. Each device is a link to its management GUI, grouped by site, cloud provider, and BIG-IQ, with a filter box and per-site buttons for finding a unit quickly. The page can be maintained in either of two ways: edited directly as HTML with no other tooling, or generated from a plain-text config by a PowerShell script.

The problem it solves is the one every estate hits eventually: the list of BIG-IP management addresses lives in a spreadsheet, a wiki page, or a hand-edited HTML file that is tedious to update and easy to break. Reach separates the data from the presentation. You edit a readable config, the script regenerates the page, and you drop the file wherever people already bookmark it. Editing is a text file; publishing is a copy.

<img width="2203" height="1207" alt="Image" src="https://github.com/user-attachments/assets/19c31a7d-aad8-445d-9b53-c7ae501a2472" />

## Two ways to use it

**Method 1: Edit the HTML directly.** `BIG-IP_Topology.html` in this repository is a complete, working page with example data. Download it, open it in a text editor, and replace the example sites and devices with your own. Nothing else is needed: no PowerShell, no build step.

**Method 2: Build with the script.** `Big-IP-Reach.ps1` turns a plain-text config into the page. You keep the config, and the script validates it and rebuilds the HTML whenever it changes. This suits a large or frequently changing estate, anyone who wants errors reported by line number before publishing, and unattended builds.

Pick one and read only that section. Both produce the same page, and the choice is not permanent: a page edited by hand can be read back into a config with `-FromHtml`, and a page built by the script can be edited by hand afterwards.

## Requirements

- Method 1: a text editor.
- Method 2: Windows PowerShell 5.1 or PowerShell 7 or greater.
- To view the page: any current browser.

## Method 1: Edit the HTML directly

Open `BIG-IP_Topology.html` in a text editor. The comment block at the top of the file is the manual: it lists how to add, disable, and rename sites, tenants, vCMP hosts, GTM devices, and cloud providers, with a reference for every field.

The data sits in the middle of the file. Each site, cloud provider, and BIG-IQ is its own `<script>` block:

```html
<script>
/* site: site01 */
SITES.push({ id:'site01', name:'Ashburn', enabled:true,
  guests:[
    { name:'ash-dmz-waf01a', fqdn:'ash-dmz-waf01a.corp.example', zone:'DMZ', nets:['10.1.10.0/24', '10.1.11.0/24'] },
    { name:'ash-dmz-waf01b', fqdn:'ash-dmz-waf01b.corp.example', zone:'DMZ', nets:['10.1.10.0/24', '10.1.11.0/24'] } ],
  hostsEnabled:true, hosts:[
    { name:'ash-vcmp01', fqdn:'ash-vcmp01.corp.example' } ],
  gtmEnabled:true, gtm:[
    { name:'ash-gtm01', fqdn:'ash-gtm01.corp.example' } ] });
</script>
```

- To change a site, edit the names and FQDNs inside its block.
- To add a site, copy a whole block including both `<script>` tags, paste it after the last site, and change the `id` in both places (the `/* site: ... */` comment and the `id:` field) along with the name and devices. Each `id` must be unique.
- To hide a block without deleting it, set `enabled:false`.
- To make a device findable by IP address, add `nets:['a.b.c.d/nn', ...]` to its entry. Subnets are never displayed.
- Leave everything below the `RENDER (do not edit)` marker alone.

Save the file and open it in a browser. Because each block is separate, a typing mistake in one block removes only that card, and a red notice at the top of the page names the block that failed. The browser console (F12) gives the line.

The script checks things that hand-editing does not: duplicate names, invalid addresses and CIDRs, and subnets attached to a device that does not exist. A hand-edited page also stays on the version it was downloaded as. To pick up a newer version, download the new script and run `.\Big-IP-Reach.ps1 -FromHtml` followed by `.\Big-IP-Reach.ps1 -Force`, as described under [Moving an existing page to a newer script](#moving-an-existing-page-to-a-newer-script) in Method 2.

## Method 2: Build with the script

### How it works

The script embeds everything it needs: the HTML boilerplate (styles, header, and render code) and a starter config. Running it with no parameters opens a menu. Running it with parameters does the same steps unattended, for a scheduled task or a CI job.

```
.\Big-IP-Reach.ps1              # interactive menu
.\Big-IP-Reach.ps1 -Export      # write the starter config
.\Big-IP-Reach.ps1 -Validate    # check the config, write nothing
.\Big-IP-Reach.ps1 -Force       # build the HTML, overwriting any existing file
.\Big-IP-Reach.ps1 -FromHtml    # read an existing page back into topology.conf
```

Files are written next to the script unless a path is given. The typical workflow is: export the template once, edit it, then build.

### The config format

One record per line, `id|category|value[|extra]`. Blank lines and lines beginning with `#` are ignored. The exported config carries a full field reference in its header comment; the short version:

```
# id        Block tag: lowercase letters, digits, hyphens. First line naming
#           an id creates the block. Blocks appear in order of first appearance.
#           all, main, nav and filter are reserved.
#
# category  type      site | cloud | bigiq          Default site. One bigiq.
#           name      Display label                 Required, once per block.
#           enabled   true | false                  Default true.
#           gtm       true | false                  Show the GTM band. Default false.
#           vcmp      true | false                  Site only. Show the vCMP Hosts band. Default true.
#           tenant    zone|device[|vcmp-host]        Site only. Zone is free text.
#           host      device                        Site only. vCMP host.
#           gtmdev    device                        Site or cloud. GTM device.
#           device    device                        Cloud or bigiq.
#           subnet    device|cidr[,cidr...]         IPv4 subnets a device serves. Not shown but searchable.
#
# device    An FQDN, an IPv4 address, or an https:// URL. The link opens
#           https://<device>. The shown name is the FQDN's first label or the
#           IP. To set a different label, write   Shown Name=device
```

A minimal site is a name and a pair of hosts:

```
site1|name|HQ
site1|host|hq-bigip01.example.com
site1|host|hq-bigip02.example.com
```

A site whose hosts should stay in the file but off the card (an rSeries or
appliance site, say) sets `vcmp|false`:

```
site2|name|Denver
site2|vcmp|false
site2|host|den-r5900-01.example.com
site2|tenant|External|den-ext-ltm01a.example.com
```

Subnets attach to a device already in the block, by shown name or FQDN:

```
dc1|subnet|chi-ext-ltm01a|198.51.100.0/24,203.0.113.0/26
dc1|subnet|chi-int-ltm01a|10.20.0.0/22
```

A fuller site with tenants, hosts, and GTM:

```
dc1|name|Chicago
dc1|gtm|true
dc1|host|chi-vcmp01.example.com
dc1|host|chi-vcmp02.example.com
dc1|tenant|External|chi-ext-ltm01a.example.com|chi-vcmp01
dc1|tenant|Internal|chi-int-ltm01a.example.com|chi-vcmp01
dc1|gtmdev|chi-gtm01.example.com

aws|type|cloud
aws|name|AWS us-east-1
aws|device|aws-use1-ltm01.example.com

bigiq|type|bigiq
bigiq|name|BIG-IQ
bigiq|device|bigiq-cm01.example.com
bigiq|device|10.0.0.6
```

### Procedure

#### 1. Export the starter config

```
.\Big-IP-Reach.ps1 -Export
```

This writes `topology.conf` next to the script, pre-filled with example sites, cloud providers, and BIG-IQ so every line type is visible.

#### 2. Edit the config

Open `topology.conf` in a text editor. Replace the example names and devices with your own. Set `enabled|false` on any block you want to keep in the file but hide from the page. Only Site 1, AWS, Azure, and BIG-IQ ship enabled; the rest are disabled spares to turn on as needed.

#### 3. Validate

```
.\Big-IP-Reach.ps1 -Validate
```

Every problem is reported with its line number and nothing is written. Fix and run again until it is clean.

#### 4. Build

```
.\Big-IP-Reach.ps1 -Force
```

This writes `BIG-IP_Topology.html` next to the config. Open it in a browser and confirm the page renders. Two data mistakes are valid syntax and so are not caught at build time; the page shows them instead: a device name in red means the entry has no FQDN or URL, and a band labeled "Unassigned zone" means a tenant has no zone.

#### 5. Publish

Copy `BIG-IP_Topology.html` wherever your team looks for it. It is one self-contained file with no dependencies.

### Moving an existing page to a newer script

A page made by an earlier version, or one maintained by hand-editing the HTML, does not need re-keying. `Import HTML` in the menu (or `-FromHtml` in batch) scans the page's data blocks and writes them out as `topology.conf`, then validates the result. In the menu the page title carries over; in batch it is printed so it can be passed back with `-Title`. Build from that config with the current script and the page picks up whatever the newer version adds. Both quote styles and fields the older page did not have (`hostsEnabled`, say) are handled; a name containing `|`, or a device name containing `=`, is noted and replaced with `/`, since the config cannot hold it. The logo is not carried across, so paste it into the new page as before.

```
.\Big-IP-Reach.ps1 -FromHtml -InputFile old.html -OutputFile topology.conf
.\Big-IP-Reach.ps1 -Force
```

## The page

- **Buttons** across the header select a site, cloud provider, or BIG-IQ. Plain click shows one; Ctrl-click (or Cmd-click) adds or removes cards for a multi-selection. `All` clears the selection.
- **The filter box** narrows the page as you type, matching device names, FQDNs, band labels (zones, vCMP Hosts, GTM), and card titles, so `vcmp` and `gtm` find those rows whatever the hostnames are. Words that name a site pick sites and OR together; the group words `sites`, `cloud`, and `bigiq` (or `iq`) pick a whole group; other words narrow rows and AND. A comma starts a new row group that keeps the same sites unless it names its own: `denver app` shows Denver's app devices, `denver chicago dmz, app` shows dmz and app devices in either site, `mumbai, cairo` shows both sites. A leading `-` (or `!`) is NOT and applies to the whole query: `-aws -azure -bigiq` shows everything except those cards, `denver -dmz` shows Denver without its dmz devices. Quoting a word (`"app"`) forces a row match when a site name contains the same text. An IPv4 address finds the devices whose subnets contain it, so the address behind an application's DNS name leads to the pair that serves it; a CIDR finds subnets that overlap it, and a partly typed address (`10.2`) narrows as you go. While you type, an address is treated as unfinished, so `204.14.123.1` also shows a device holding `204.14.123.128/25`; press `Enter` to read the field exactly as written and see only the subnet that contains the address. Editing the field returns to as-you-type matching. IPv6 is not supported. Site or group words in the filter add to the button selection, so three selected sites plus `cloud iq` show all five cards. `Alt+F` focuses the filter; `Alt+C` clears it; `Escape` also clears and returns to `All`.
- **The header** grows to as many button rows as needed and never overlaps the logo, title, or filter.

## The logo

The header image is embedded in the generated HTML as a placeholder. To replace it, open the HTML in a text editor and follow the `LOGO` comment near the top: convert a PNG to base64 and paste it into the `src` of the `<img>` tag. Rebuilding from the config restores the placeholder, so to make a logo permanent, make the same edit once inside `Big-IP-Reach.ps1`.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Disclaimer

- This solution is **NOT** officially endorsed, supported, or maintained by F5 Inc.
- F5 Inc. retains all rights to their trademarks, including but not limited to "F5", "BIG-IP", "BIG-IQ", "TMOS", "vCMP", and related marks.
- This is an independent, community-developed tool that references F5 products but is not affiliated with F5 Inc.
- For official F5 support and solutions, please contact F5 Inc. directly.

**Technical Disclaimer:**

- This software is provided "AS IS" without warranty of any kind
- The authors and contributors are not responsible for any damages or issues that may arise from its use
- Always test thoroughly in non-production environments before deployment
- Review and understand all code before deploying to production systems

By using this software, you acknowledge that you have read and understood these disclaimers and agree to use this tool at your own risk.
