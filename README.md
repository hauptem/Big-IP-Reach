# BIG-IP-Reach

An offline, single-file HTML directory for reaching F5 BIG-IP management interfaces from one page. Each device is a link to its management GUI, grouped by site, cloud provider, and BIG-IQ, with a filter box and per-site buttons for finding a unit quickly. The page is generated from a plain-text config by a PowerShell script.

The problem it solves is the one every estate hits eventually: the list of BIG-IP management addresses lives in a spreadsheet, a wiki page, or a hand-edited HTML file that is tedious to update and easy to break. 

<img width="2203" height="1207" alt="Image" src="https://github.com/user-attachments/assets/19c31a7d-aad8-445d-9b53-c7ae501a2472" />

## How it works

The script embeds everything it needs: the HTML boilerplate (styles, header, and render code) and a starter config. Running it with no parameters opens a menu. 

```
.\Big-IP-Reach.ps1              # interactive menu
.\Big-IP-Reach.ps1 -Export      # write the starter config
.\Big-IP-Reach.ps1 -Validate    # check the config, write nothing
.\Big-IP-Reach.ps1 -Force       # build the HTML, overwriting any existing file
.\Big-IP-Reach.ps1 -FromHtml    # read an existing page back into topology.conf
```

The typical workflow is: export the template once, edit it, then build.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7 or greater.

## The config format

One record per line, `id|category|value[|extra]`. Blank lines and lines beginning with `#` are ignored. The exported config carries a full field reference in its header comment; the short version:

```
# id        Block tag: lowercase letters, digits, hyphens. First line naming
#           an id creates the block. Blocks appear in order of first appearance.
#
# category  type      site | cloud | bigiq          Default site. One bigiq.
#           name      Display label                 Required, once per block.
#           enabled   true | false                  Default true.
#           gtm       true | false                  Show the GTM band. Default false.
#           vcmp      true | false                  Site only. Show the vCMP Hosts band. Default true.
#           tenant    zone|device[|vcmp-host]       Site only. Zone is free text.
#           host      device                        Site only. vCMP host.
#           gtmdev    device                        Site or cloud. GTM device.
#           device    device                        Cloud or bigiq.
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

The examples conf files contains five complete configs modeled on different kinds of organizations (a retail bank, a cloud-first SaaS company, a global manufacturer, a university, and a managed service provider), plus a 50-site stress config.

## Procedure

### 1. Export the starter config

```
.\Big-IP-Reach.ps1 -Export
```

This writes `topology.conf` next to the script, pre-filled with example sites, cloud providers, and BIG-IQ so every line type is visible.

### 2. Edit the config

Open `topology.conf` in a text editor. Replace the example names and devices with your own. Set `enabled|false` on any block you want to keep in the file but hide from the page. Only Site 1, AWS, Azure, and BIG-IQ ship enabled; the rest are disabled spares to turn on as needed.

### 3. Validate

```
.\Big-IP-Reach.ps1 -Validate
```

Every problem is reported with its line number and nothing is written. Fix and run again until it is clean.

### 4. Build

```
.\Big-IP-Reach.ps1 -Force
```

This writes `BIG-IP_Topology.html` next to the config. Open it in a browser and confirm the page renders. Two data mistakes are valid syntax and so are not caught at build time; the page shows them instead: a device name in red means the entry has no FQDN or URL, and a band labeled "Unassigned zone" means a tenant has no zone.

### 5. Publish

Copy `BIG-IP_Topology.html` wherever your team looks for it. It is one self-contained file with no dependencies.

## The page

- **Buttons** across the header select a site, cloud provider, or BIG-IQ. Plain click shows one; Ctrl-click (or Cmd-click) adds or removes cards for a multi-selection. `All` clears the selection.
- **The filter box** narrows the page as you type, matching device names, FQDNs, band labels (zones, vCMP Hosts, GTM), and card titles, so `vcmp` and `gtm` find those rows whatever the hostnames are. Words that name a site pick sites and OR together; the group words `sites`, `cloud`, and `bigiq` (or `iq`) pick a whole group; other words narrow rows and AND. A comma starts a new row group that keeps the same sites unless it names its own: `denver app` shows Denver's app devices, `denver chicago dmz, app` shows dmz and app devices in either site, `mumbai, cairo` shows both sites. A leading `-` (or `!`) is NOT and applies to the whole query: `-aws -azure -bigiq` shows everything except those cards, `denver -dmz` shows Denver without its dmz devices. Quoting a word (`"app"`) forces a row match when a site name contains the same text. Site or group words in the filter add to the button selection, so three selected sites plus `cloud iq` show all five cards. `Alt+F` focuses the filter; `Alt+C` clears it; `Escape` also clears and returns to `All`.

## Moving an existing page to a newer script

A page made by an earlier version does not need re-keying. `Import HTML` in the menu (or `-FromHtml` in batch) scans the page's data blocks and writes them out as `topology.conf`, then validates the result; the page title carries over. Build from that config with the current script and the page picks up whatever the newer version adds. Both quote styles and fields the older page did not have (`hostsEnabled`, say) are handled; a name containing `|` is noted and replaced with `/`, since the config cannot hold it. The logo is not carried across, so paste it into the new page as before.

```
.\Big-IP-Reach.ps1 -FromHtml -InputFile old.html -OutputFile topology.conf
.\Big-IP-Reach.ps1 -Force
```

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
