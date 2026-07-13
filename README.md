<!--
  Layout notes:
  - Every gap (vertical and horizontal) is exactly 10px, baked into the SVGs
    as transparent padding: cards carry a 10px bottom pad (except the footer)
    and a 10px right pad (except the last card of each row).
  - Rows use <div> (no margins, unlike <p>) and images are butted together
    with zero whitespace so widths are exact; each row sums to 800px.
  - align="top" (vertical-align: top) collapses each row's line box to the
    image height, removing the font-descent gap that default baseline
    alignment adds below each row. Note: the legacy align="bottom" maps to
    vertical-align: baseline, which does NOT remove it.
-->
<div align="center"><a href="https://joseph.kribs.net"><img src="cards/header.svg" alt="Joe Kribs — Data Analytics Manager" align="top" width="800"></a></div>

<div align="center"><a href="https://github.com/jellyfin/Swiftfin"><img src="cards/swiftfin.svg" alt="Swiftfin — Native Jellyfin Client for iOS and tvOS" align="top" width="800"></a></div>

<div align="center"><a href="https://github.com/JPKribs/jellyfin-plugin-custompages"><img src="cards/custompages.svg" alt="Custom Pages" align="top"></a><a href="https://github.com/JPKribs/jellyfin-plugin-ddns"><img src="cards/ddns.svg" alt="DDNS" align="top"></a><a href="https://github.com/JPKribs/jellyfin-plugin-livechannels"><img src="cards/livechannels.svg" alt="Live Channels" align="top"></a></div>

<div align="center"><a href="https://github.com/JPKribs/jellyfin-plugin-episodepostergenerator"><img src="cards/poster.svg" alt="Episode Poster Generator" align="top"></a><a href="https://github.com/JPKribs/jellyfin-plugin-serversync"><img src="cards/sync.svg" alt="Server Sync" align="top"></a><a href="https://github.com/JPKribs/jellyfin-plugin-usermanagement"><img src="cards/usermgmt.svg" alt="User Management" align="top"></a><a href="https://github.com/JPKribs/jellyfin-plugin-youtubeaudio"><img src="cards/youtube.svg" alt="YouTube Audio" align="top"></a></div>

<div align="center"><a href="https://joseph.kribs.net"><img src="cards/footer.svg" alt="joseph.kribs.net • joseph@kribs.net • Littleton, CO" align="top" width="800"></a></div>
