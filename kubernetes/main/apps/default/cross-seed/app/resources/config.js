// Note: Cross-Seed vars should be escaped with $${VAR_NAME} to avoid any interpolation by Flux
module.exports = {
  delay: 20,
  qbittorrentUrl: "http://qbittorrent.default.svc.cluster.local:8080",
  torznab: [
    `http://prowlarr.default.svc.cluster.local:9696/3/api?apikey=$${process.env.PROWLARR_API_KEY}`, // mam
    `http://prowlarr.default.svc.cluster.local:9696/5/api?apikey=$${process.env.PROWLARR_API_KEY}`, // hds
    `http://prowlarr.default.svc.cluster.local:9696/9/api?apikey=$${process.env.PROWLARR_API_KEY}`, // ipt
    `http://prowlarr.default.svc.cluster.local:9696/11/api?apikey=$${process.env.PROWLARR_API_KEY}`, // dc
    `http://prowlarr.default.svc.cluster.local:9696/14/api?apikey=$${process.env.PROWLARR_API_KEY}`, // thhq
    `http://prowlarr.default.svc.cluster.local:9696/16/api?apikey=$${process.env.PROWLARR_API_KEY}`, // tos
    `http://prowlarr.default.svc.cluster.local:9696/17/api?apikey=$${process.env.PROWLARR_API_KEY}`, // mlk
    `http://prowlarr.default.svc.cluster.local:9696/53/api?apikey=$${process.env.PROWLARR_API_KEY}`, // fnp
    `http://prowlarr.default.svc.cluster.local:9696/86/api?apikey=$${process.env.PROWLARR_API_KEY}`, // uplcx
  ],
  port: process.env.CROSSSEED_PORT || 80,
  apiAuth: false,
  action: "inject",
  includeEpisodes: false,
  includeSingleEpisodes: true,
  includeNonVideos: true,
  duplicateCategories: true,
  matchMode: "safe",
  skipRecheck: true,
  outputDir: "/config",
  torrentDir: "/qbittorrent/qBittorrent/BT_backup",
};