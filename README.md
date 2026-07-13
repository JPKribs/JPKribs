<!--
  Layout notes:
  - Every gap (vertical and horizontal) is exactly 10px, baked into the SVGs
    as transparent padding: cards carry a 10px bottom pad (except the footer)
    and the plugin cards a 5px pad on EACH side.
  - Plugin cards are all one uniform width (192.5px visible, 202.5px with
    gutters) and live in a single centered <div> with zero whitespace
    between images, so they wrap like a centered flex row: 4 per row when
    the container fits 810px (visible span exactly 800, matching the
    full-width cards), then 3/2/1 as it narrows — no hardcoded rows.
  - align="top" (vertical-align: top) collapses each line box to the image
    height, removing the font-descent gap that default baseline alignment
    adds below each row. Note: the legacy align="bottom" maps to
    vertical-align: baseline, which does NOT remove it.
  - Responsive: every card is a <picture> whose <source media="(max-width:
    767px)"> swaps in a full-width 800px "-mobile" variant with larger type,
    so phones (including the GitHub app) get a uniform stack of full-width
    cards, each still individually linked. Wider-but-narrow containers are
    handled by the wrapping above. Mobile cards bake a 20px transparent
    bottom pad (footer excepted), which at half scale matches the desktop
    10px gaps.
-->
<div align="center"><a href="https://joseph.kribs.net"><picture><source media="(max-width: 767px)" srcset="cards/header-mobile.svg"><img src="cards/header.svg" alt="Joe Kribs — Data Analytics Manager" align="top" width="800"></picture></a></div>

<div align="center"><a href="https://github.com/jellyfin/Swiftfin"><picture><source media="(max-width: 767px)" srcset="cards/swiftfin-mobile.svg"><img src="cards/swiftfin.svg" alt="Swiftfin — Native Jellyfin Client for iOS and tvOS" align="top" width="800"></picture></a></div>

<div align="center"><a href="https://github.com/JPKribs/jellyfin-plugin-custompages"><picture><source media="(max-width: 767px)" srcset="cards/custompages-mobile.svg"><img src="cards/custompages.svg" alt="Custom Pages" align="top"></picture></a><a href="https://github.com/JPKribs/jellyfin-plugin-ddns"><picture><source media="(max-width: 767px)" srcset="cards/ddns-mobile.svg"><img src="cards/ddns.svg" alt="DDNS" align="top"></picture></a><a href="https://github.com/JPKribs/jellyfin-plugin-livechannels"><picture><source media="(max-width: 767px)" srcset="cards/livechannels-mobile.svg"><img src="cards/livechannels.svg" alt="Live Channels" align="top"></picture></a><a href="https://github.com/JPKribs/jellyfin-plugin-episodepostergenerator"><picture><source media="(max-width: 767px)" srcset="cards/poster-mobile.svg"><img src="cards/poster.svg" alt="Episode Poster Generator" align="top"></picture></a><a href="https://github.com/JPKribs/jellyfin-plugin-serversync"><picture><source media="(max-width: 767px)" srcset="cards/sync-mobile.svg"><img src="cards/sync.svg" alt="Server Sync" align="top"></picture></a><a href="https://github.com/JPKribs/jellyfin-plugin-usermanagement"><picture><source media="(max-width: 767px)" srcset="cards/usermgmt-mobile.svg"><img src="cards/usermgmt.svg" alt="User Management" align="top"></picture></a><a href="https://github.com/JPKribs/jellyfin-plugin-youtubeaudio"><picture><source media="(max-width: 767px)" srcset="cards/youtube-mobile.svg"><img src="cards/youtube.svg" alt="YouTube Audio" align="top"></picture></a></div>

<div align="center"><a href="https://joseph.kribs.net"><picture><source media="(max-width: 767px)" srcset="cards/footer-mobile.svg"><img src="cards/footer.svg" alt="joseph.kribs.net • joseph@kribs.net • Littleton, CO" align="top" width="800"></picture></a></div>
