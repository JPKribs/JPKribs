<!--
  Layout notes:
  - GitHub's profile README column (article.markdown-body, measured Jul
    2026): FIXED 846px at viewports ≥1280; fluid below (viewport−434 at
    1012-1279, viewport−370 at 768-1011, viewport−82 under 768). GitHub
    strips CSS, so a fixed-size card grid can only fill the column exactly
    in the fixed ≥1280 tier — everywhere else only a 100%-width image can
    track the fluid column. Hence:
      * ≥1280: desktop grid. Static rows sized flush to 846, flex-grow
        style: 4 × 203.75 + gutters and 3 × 275 + gutters (each row sums to
        845, leaving 1px slack so rounding can never wrap a card).
      * ≤1279: every plugin card swaps (via <picture><source>) to its
        full-width "-mobile" variant, whose 1600px intrinsic width always
        exceeds the column so max-width:100% scales it to fill exactly.
      * ≤767: the header/Swiftfin/footer cards also swap to mobile variants
        with larger type for phone legibility. They carry width="100%" so
        they fill the column at every size (the old width="800" capped them
        under the 846 column).
  - Gaps are baked into the SVGs as transparent padding: desktop cards
    carry a 10px right gutter (except the last card of each row) and a 10px
    bottom pad (except the footer); mobile cards a 20px bottom pad, which
    scales with the card so stacked gaps stay proportional.
  - Rows use <div> (no margins, unlike <p>) and images are butted together
    with zero whitespace so widths are exact. All 7 plugin cards live in one
    <div>; the fixed 846 column makes the 4/3 wrap static.
  - align="top" (vertical-align: top) collapses each line box to the image
    height, removing the font-descent gap that default baseline alignment
    adds below each row. Note: the legacy align="bottom" maps to
    vertical-align: baseline, which does NOT remove it.
-->
<div align="center"><a href="https://joseph.kribs.net"><picture><source media="(max-width: 767px)" srcset="cards/header-mobile.svg"><img src="cards/header.svg" alt="Joe Kribs — Data Analytics Manager" align="top" width="100%"></picture></a></div>

<div align="center"><a href="https://github.com/jellyfin/Swiftfin"><picture><source media="(max-width: 767px)" srcset="cards/swiftfin-mobile.svg"><img src="cards/swiftfin.svg" alt="Swiftfin — Native Jellyfin Client for iOS and tvOS" align="top" width="100%"></picture></a></div>

<div align="center"><a href="https://github.com/JPKribs/jellyfin-plugin-custompages"><picture><source media="(max-width: 1279px)" srcset="cards/custompages-mobile.svg"><img src="cards/custompages.svg" alt="Custom Pages" align="top"></picture></a><a href="https://github.com/JPKribs/jellyfin-plugin-ddns"><picture><source media="(max-width: 1279px)" srcset="cards/ddns-mobile.svg"><img src="cards/ddns.svg" alt="DDNS" align="top"></picture></a><a href="https://github.com/JPKribs/jellyfin-plugin-livechannels"><picture><source media="(max-width: 1279px)" srcset="cards/livechannels-mobile.svg"><img src="cards/livechannels.svg" alt="Live Channels" align="top"></picture></a><a href="https://github.com/JPKribs/jellyfin-plugin-episodepostergenerator"><picture><source media="(max-width: 1279px)" srcset="cards/poster-mobile.svg"><img src="cards/poster.svg" alt="Episode Poster Generator" align="top"></picture></a><a href="https://github.com/JPKribs/jellyfin-plugin-serversync"><picture><source media="(max-width: 1279px)" srcset="cards/sync-mobile.svg"><img src="cards/sync.svg" alt="Server Sync" align="top"></picture></a><a href="https://github.com/JPKribs/jellyfin-plugin-usermanagement"><picture><source media="(max-width: 1279px)" srcset="cards/usermgmt-mobile.svg"><img src="cards/usermgmt.svg" alt="User Management" align="top"></picture></a><a href="https://github.com/JPKribs/jellyfin-plugin-youtubeaudio"><picture><source media="(max-width: 1279px)" srcset="cards/youtube-mobile.svg"><img src="cards/youtube.svg" alt="YouTube Audio" align="top"></picture></a></div>

<div align="center"><a href="https://joseph.kribs.net"><picture><source media="(max-width: 767px)" srcset="cards/footer-mobile.svg"><img src="cards/footer.svg" alt="joseph.kribs.net • joseph@kribs.net • Littleton, CO" align="top" width="100%"></picture></a></div>
