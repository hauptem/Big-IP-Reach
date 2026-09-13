# F5-BIG-IP-Reach

A powershell script that exports an offline, single HTML file that builds a table directory for reaching an organizations F5 BIG-IP management interfaces. This is just a tool to easily create an offline (or hosted) html file to map an organizations entire Big-IP topology with links to all needed management interfaces. Most orgs share a bookmarks.html file; some host a static page with plain links. This allows for a bit more functionality with regard to site selection and searching.

<img width="1591" height="1295" alt="Image" src="https://github.com/user-attachments/assets/ac43d668-875a-48f3-be24-3fa36880bcbd" />
<img width="2321" height="1321" alt="Image" src="https://github.com/user-attachments/assets/e0dc8d53-1ceb-4e1c-8589-44f5910f4079" />

## How it works

```
.\Big-IP-Reach.ps1             # interactive menu
.\Big-IP-Reach.ps1 -Export      # write the starter config
.\Big-IP-Reach.ps1 -Validate    # check the config, write nothing
.\Big-IP-Reach.ps1 -Force       # build the HTML, overwriting any existing file
```

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
#           tenant    zone|device[|vcmp-host]        Site only. Zone is free text.
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

## The page

- **Buttons** Click one to show that site; Ctrl-click (or Cmd-click) to add or remove sites for multi-selection. `All` clears the selection.
- **The filter box** narrows the page as you type, matching device names, FQDNs, zones, hosts, and card titles. Terms separated by spaces are OR'd. `Alt+F` focuses the filter; `Alt+C` clears it; `Escape` also clears and returns to `All`.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Disclaimer

- This solution is **NOT** officially endorsed, supported, or maintained by F5 Inc.
- F5 Inc. retains all rights to their trademarks, including but not limited to "F5", "BIG-IP", "BIG-IQ", "TMOS", and related marks.
- This is an independent, community-developed tool that references F5 products but is not affiliated with F5 Inc.
- For official F5 support and solutions, please contact F5 Inc. directly.

**Technical Disclaimer:**

- This software is provided "AS IS" without warranty of any kind
- The authors and contributors are not responsible for any damages or issues that may arise from its use
- Always test thoroughly in non-production environments before deployment
- Review and understand all code before deploying to production systems

By using this software, you acknowledge that you have read and understood these disclaimers and agree to use this tool at your own risk.
