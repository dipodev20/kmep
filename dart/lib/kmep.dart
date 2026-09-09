// KMEP — a from-scratch YouTube extraction library for Dart.
// Copyright (C) 2026 dipodev20
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

/// KMEP — a from-scratch YouTube extraction library for Dart, built to be
/// the "evolution of NewPipeExtractor": InnerTube's multi-client fallback
/// (ANDROID_VR / WEB / IOS / WEB_SAFARI / TV), on-device signature/`n`
/// resolution via real `player.js` execution, on-device PO token (BotGuard)
/// generation with no external server, and a circuit-breaker-friendly
/// remote config — all behind one small facade class, [Kmep].
///
/// Start with [Kmep]. Everything else in this export list is here for
/// advanced use: swapping pieces (your own [CacheManager], a custom
/// [PoTokenProvider], per-client overrides via [RemoteConfig]) or for
/// building your own facade if the default one doesn't fit your app.
library kmep;

// ---- Main entry point --------------------------------------------------
export 'src/kmep_client.dart';

// ---- Models --------------------------------------------------------------
export 'src/models/kmep_models.dart'
    show
        VideoInfo,
        KMEPStream,
        VideoSearchResult,
        SearchResultPage,
        ChannelInfo,
        CommentInfo,
        KMEPErrorCode,
        KMEPException;

// ---- Search / shorts feed -------------------------------------------------
export 'src/search/search_client.dart'
    show SearchClient, ShortsFeedPage, kShortsSearchParams;

// ---- Platform integration points (implement these on new platforms) ------
export 'src/resolvers/stream_resolver.dart'
    show
        JsRuntime,
        StreamResolver,
        preparePlayerJs,
        discoverResolveFnScript,
        browserShimScript;
export 'src/core/po_token.dart' show PoTokenProvider, NoOpPoTokenProvider;
export 'src/core/botguard_pot_provider.dart' show BotGuardJsPoTokenProvider;
export 'src/core/watch_page_meta.dart'
    show
        WatchPageMetaProvider,
        HttpWatchPageMetaProvider,
        CachedWatchPageMetaProvider,
        WatchPageMeta;
export 'src/core/cache_manager.dart' show CacheManager, InMemoryCacheManager;
export 'src/runtimes/process_js_runtime.dart' show NodeProcessJsRuntime;

// ---- Configuration ---------------------------------------------------------
export 'src/core/remote_config.dart' show RemoteConfig, RemoteConfigLoader;
export 'src/core/infra.dart';

// ---- Lower-level building blocks (used internally by Kmep; exported for
// consumers who want to compose their own pipeline instead of the facade,
// the same way NewPipeExtractor exposes StreamExtractor alongside NewPipe) --
export 'src/clients/client_configs.dart';
export 'src/clients/innertube_client.dart' show InnerTubeClient;
export 'src/parsers/player_parser.dart' show PlayerParser;
export 'src/resolvers/stream_resolver.dart' show StreamResolver;
export 'src/core/extraction_orchestrator.dart'
    show ExtractionOrchestrator, BackendFallback;
export 'src/core/po_token.dart'
    show
        PoTokenProvider,
        NoOpPoTokenProvider,
        BgutilScriptPoTokenProvider,
        BgutilHttpPoTokenProvider;
export 'src/core/botguard_pot_provider.dart'
    show BotGuardJsPoTokenProvider, parseLooseJson;
