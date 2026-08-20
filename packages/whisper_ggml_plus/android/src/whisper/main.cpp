#include <android/log.h>
#include "main.h"
#include "src/whisper.h"

#define DR_WAV_IMPLEMENTATION
#include "src/examples/dr_wav.h"

#include <cmath>
#include <atomic>
#include <fstream>
#include <cstdio>
#include <string>
#include <thread>
#include <vector>
#include <mutex>
#include <iostream>
#include <chrono>
#include "json/json.hpp"
#include <stdio.h>

using json = nlohmann::json;

enum class whisper_vad_mode {
    auto_mode,
    disabled,
    enabled,
};

struct whisper_params
{
    int32_t seed = -1;
    int32_t n_threads = std::min(4, (int32_t)std::thread::hardware_concurrency());

    int32_t n_processors = 1;
    int32_t offset_t_ms = 0;
    int32_t offset_n = 0;
    int32_t duration_ms = 0;
    int32_t max_context = -1;
    int32_t max_len = 0;
    int32_t best_of = 5;
    int32_t beam_size = -1;

    float word_thold = 0.01f;
    float entropy_thold = 2.40f;
    float logprob_thold = -1.00f;

    bool verbose = false;
    bool print_special_tokens = false;
    bool speed_up = false;
    bool translate = false;
    bool diarize = false;
    bool no_fallback = false;
    bool output_txt = false;
    bool output_vtt = false;
    bool output_srt = false;
    bool output_wts = false;
    bool output_csv = false;
    bool print_special = false;
    bool print_colors = false;
    bool print_progress = false;
    bool no_timestamps = false;
    bool split_on_word = false;
    // FORK: suppress non-speech tokens so ambient noise and music are not
    // emitted as text (music notes, bracketed sound tags). Locked on by
    // docs/engine-architecture.md; upstream never wired this to whisper.cpp.
    bool suppress_nst = true;
    whisper_vad_mode vad_mode = whisper_vad_mode::auto_mode;

    std::string language = "id";
    std::string prompt;
    std::string model = "";
    std::string audio = "";
    std::string vad_model_path = "";
    std::vector<std::string> fname_inp = {};
    std::vector<std::string> fname_outp = {};
};

static whisper_vad_mode parse_vad_mode(const json & json_body) {
    const std::string vad_mode = json_body.value("vad_mode", std::string("auto"));
    if (vad_mode == "disabled") {
        return whisper_vad_mode::disabled;
    }
    if (vad_mode == "enabled") {
        return whisper_vad_mode::enabled;
    }
    return whisper_vad_mode::auto_mode;
}

static struct whisper_context * g_ctx = nullptr;
static std::string g_model_path = "";
static std::mutex g_mutex;
static std::atomic<bool> g_should_abort(false);

static void dispose_context_locked() {
    if (g_ctx != nullptr) {
        whisper_free(g_ctx);
        g_ctx = nullptr;
    }
    g_model_path.clear();
}

static bool abort_callback(void* user_data) {
    return g_should_abort.load();
}

// FORK: transcription progress, 0-100, published for the Dart side to read
// via get_progress(). Polling an atomic avoids pulling in the Dart API DL
// and native ports just to drive a progress bar, and whisper.cpp invokes the
// callback often enough that sampling it looks identical to being pushed.
static std::atomic<int> g_progress(0);

static void progress_callback_fn(struct whisper_context * /*ctx*/,
                                 struct whisper_state * /*state*/,
                                 int progress,
                                 void * /*user_data*/) {
    g_progress.store(progress);
}

// FORK: nlohmann's .value() throws (type_error.302) when a key is present
// but null -- which is exactly what the Dart layer sends for unset optional
// fields. Treat present-but-null as absent.
template <typename T>
static T json_get(const json & body, const char * key, T fallback) {
    const auto it = body.find(key);
    if (it == body.end() || it->is_null()) {
        return fallback;
    }
    return it->template get<T>();
}

char *jsonToChar(json jsonData)
{
    try {
        // Ensure ASCII encoding to avoid UTF-8 issues across FFI boundary
        // Non-ASCII characters (Korean, etc.) will be escaped as \uXXXX
        // Use 'replace' instead of 'strict' to handle malformed UTF-8 from Whisper output
        // (e.g., truncated multibyte sequences like 0xEC without following bytes)
        std::string result = jsonData.dump(-1, ' ', true, nlohmann::json::error_handler_t::replace);
        char *ch = new char[result.size() + 1];
        if (ch) {
            strcpy(ch, result.c_str());
        }
        return ch;
    } catch (const std::exception& e) {
        // Fallback for absolute safety
        std::string errorJson = "{\"@type\":\"error\",\"message\":\"JSON serialization failed\"}";
        char *ch = new char[errorJson.size() + 1];
        strcpy(ch, errorJson.c_str());
        return ch;
    }
}

json transcribe(json jsonBody)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    
    g_should_abort.store(false);

    whisper_params params;
    params.n_threads = jsonBody["threads"];
    params.verbose = jsonBody["is_verbose"];
    params.translate = jsonBody["is_translate"];
    params.language = jsonBody["language"];
    params.print_special_tokens = jsonBody["is_special_tokens"];
    params.no_timestamps = jsonBody["is_no_timestamps"];
    params.model = jsonBody["model"];
    params.audio = jsonBody["audio"];
    params.split_on_word = jsonBody["split_on_word"];
    params.diarize = jsonBody["diarize"];
    params.speed_up = jsonBody["speed_up"];
    params.vad_mode = parse_vad_mode(jsonBody);
    // FORK: was jsonBody.value(...), which threw when Dart sent an explicit
    // null (the resolver deliberately leaves this null when split_on_word
    // is set, since VAD does not apply).
    params.vad_model_path = json_get(jsonBody, "vad_model_path", std::string(""));
    // FORK: parameters upstream never read off the request.
    params.no_fallback = json_get(jsonBody, "no_fallback", false);
    params.suppress_nst = json_get(jsonBody, "suppress_nst", true);
    params.prompt = json_get(jsonBody, "initial_prompt", std::string(""));

    json jsonResult;
    jsonResult["@type"] = "transcribe";

    if (g_ctx == nullptr || g_model_path != params.model) {
        dispose_context_locked();
        
        whisper_context_params cparams = whisper_context_default_params();
        cparams.use_gpu = false;
        cparams.flash_attn = false;

        g_ctx = whisper_init_from_file_with_params(params.model.c_str(), cparams);
        if (g_ctx != nullptr) {
            g_model_path = params.model;
        }
    }

    if (g_ctx == nullptr)
    {
        jsonResult["@type"] = "error";
        jsonResult["message"] = "failed to initialize whisper context (possibly OOM)";
        return jsonResult;
    }

    std::vector<float> pcmf32;
    {
        drwav wav;
        if (!drwav_init_file(&wav, params.audio.c_str(), NULL))
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = " failed to open WAV file ";
            return jsonResult;
        }

        // FORK: whisper_full() below assumes its samples are 16 kHz -- there is
        // no rate argument and no conversion. Upstream fed drwav's output
        // straight in, so a WAV at any other rate was silently interpreted at
        // the wrong speed and returned a fluent, confident, wrong transcript
        // rather than an error. Refuse it instead.
        if (wav.sampleRate != WHISPER_SAMPLE_RATE)
        {
            const uint32_t actual_rate = wav.sampleRate;
            drwav_uninit(&wav);
            jsonResult["@type"] = "error";
            jsonResult["message"] = "WAV must be " + std::to_string(WHISPER_SAMPLE_RATE) +
                                    " Hz, got " + std::to_string(actual_rate) + " Hz";
            return jsonResult;
        }

        int n = wav.totalPCMFrameCount;
        std::vector<int16_t> pcm16(n * wav.channels);
        drwav_read_pcm_frames_s16(&wav, n, pcm16.data());
        drwav_uninit(&wav);

        pcmf32.resize(n);
        if (wav.channels == 1) {
            for (int i = 0; i < n; i++) pcmf32[i] = float(pcm16[i]) / 32768.0f;
        } else {
            for (int i = 0; i < n; i++) pcmf32[i] = float(pcm16[2 * i] + pcm16[2 * i + 1]) / 65536.0f;
        }
    }

    const int model_n_text_layer = whisper_model_n_text_layer(g_ctx);
    const int model_n_vocab = whisper_model_n_vocab(g_ctx);
    const bool is_turbo = (model_n_text_layer == 4 && model_n_vocab == 51866);
    
    __android_log_print(ANDROID_LOG_DEBUG, "WhisperFlutter", 
                        "[DEBUG] Model info - n_text_layer: %d, n_vocab: %d, is_turbo: %d", 
                        model_n_text_layer, model_n_vocab, is_turbo);

    // FORK: upstream inferred the strategy purely from model shape, so a
    // caller that requires greedy got it only as a side effect of not using
    // a turbo model. Default still follows upstream; "greedy"/"beam" make it
    // an explicit choice.
    whisper_sampling_strategy strategy = is_turbo ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY;
    const std::string strategy_name = json_get(jsonBody, "sampling_strategy", std::string("auto"));
    if (strategy_name == "greedy") {
        strategy = WHISPER_SAMPLING_GREEDY;
    } else if (strategy_name == "beam") {
        strategy = WHISPER_SAMPLING_BEAM_SEARCH;
    }

    whisper_full_params wparams = whisper_full_default_params(strategy);
    
    wparams.print_realtime = false;
    wparams.print_progress = false;
    wparams.print_timestamps = !params.no_timestamps;
    wparams.translate = params.translate;
    wparams.language = params.language.c_str();
    wparams.n_threads = params.n_threads;
    wparams.split_on_word = params.split_on_word;
    wparams.audio_ctx = params.speed_up ? 768 : 0; // Use smaller audio context for speedUp
    wparams.single_segment = false;

    // FORK: upstream unconditionally disabled VAD whenever split_on_word was
    // set, on the grounds that word-level output "requires stable timestamps".
    // That is over-conservative for how this fork reads results. Word data is
    // emitted through whisper_full_get_segment_t0/t1 (see build_result below),
    // and those accessors DO remap through state->vad_mapping_table
    // (whisper.cpp, map_processed_to_original_time). The accessor that returns
    // un-remapped, VAD-relative times is whisper_full_get_token_data, which
    // this fork never calls. Within a speech run the mapping is exact -- the
    // run is memcpy'd verbatim into the filtered buffer -- with extra
    // interpolation points every 200ms; error can only appear across the
    // synthetic padding between runs, where by construction there are no words.
    // VAD is therefore governed by vad_mode alone, as it is without
    // split_on_word. Re-apply on any upstream bump; ios/Classes has its own
    // copy of this logic.
    //
    // Note wparams.vad_params is left at whisper_vad_default_params():
    // threshold 0.5, min_speech 250ms, min_silence 100ms, speech_pad 30ms,
    // samples_overlap 0.1s. Inherited deliberately, not tuned -- record a
    // measurement in docs/progress.md before changing any of them.
    if (params.vad_mode == whisper_vad_mode::disabled) {
        wparams.vad = false;
    } else if (!params.vad_model_path.empty()) {
        wparams.vad = true;
        wparams.vad_model_path = params.vad_model_path.c_str();
    } else if (params.vad_mode == whisper_vad_mode::enabled) {
        jsonResult["@type"] = "error";
        jsonResult["message"] =
            "VAD was explicitly enabled but no vad_model_path was provided for this platform";
        return jsonResult;
    } else {
        wparams.vad = false;
    }

    // FORK: only meaningful when beam search actually won above.
    if (is_turbo && strategy == WHISPER_SAMPLING_BEAM_SEARCH) {
        wparams.beam_search.beam_size = 3;
        __android_log_print(ANDROID_LOG_DEBUG, "WhisperFlutter",
                            "[DEBUG] Turbo model detected - using beam search (beam_size=3)");
    }

    // FORK: locked inference params from docs/engine-architecture.md that
    // upstream never applied.
    //
    // no_fallback pins decoding to a single pass. Without it whisper.cpp
    // re-decodes any window that fails its quality thresholds at rising
    // temperatures, which on weak hardware or difficult audio can stall for
    // a very long time -- the exact hazard the doc cites.
    if (params.no_fallback) {
        wparams.temperature = 0.0f;
        wparams.temperature_inc = 0.0f;
    }
    wparams.suppress_nst = params.suppress_nst;

    // Soft bias toward supplied vocabulary. params outlives whisper_full().
    if (!params.prompt.empty()) {
        wparams.initial_prompt = params.prompt.c_str();
    }

    g_progress.store(0);
    wparams.progress_callback = progress_callback_fn;
    wparams.progress_callback_user_data = nullptr;

    if (params.split_on_word) {
        wparams.max_len = 1;
        wparams.token_timestamps = true;
    }
    
    wparams.abort_callback = abort_callback;
    wparams.abort_callback_user_data = nullptr;

    __android_log_print(ANDROID_LOG_DEBUG, "WhisperFlutter",
                        "[DEBUG] Transcription params - threads: %d, speed_up: %d, no_timestamps: %d, single_segment: %d, split_on_word: %d, max_len: %d",
                        wparams.n_threads, params.speed_up, wparams.no_timestamps, wparams.single_segment, wparams.split_on_word, wparams.max_len);

    auto start_time = std::chrono::high_resolution_clock::now();

    if (whisper_full(g_ctx, wparams, pcmf32.data(), pcmf32.size()) != 0)
    {
        if (g_should_abort.load()) {
            jsonResult["@type"] = "aborted";
            jsonResult["message"] = "transcription aborted by user";
            g_should_abort.store(false);
            return jsonResult;
        }
        jsonResult["@type"] = "error";
        jsonResult["message"] = "failed to process audio";
        return jsonResult;
    }

    auto end_time = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count();

    __android_log_print(ANDROID_LOG_DEBUG, "WhisperFlutter", "[DEBUG] Transcription completed in %lldms", (int)duration);

    g_progress.store(100);

    const int n_segments = whisper_full_n_segments(g_ctx);
    std::vector<json> segmentsJson = {};
    std::string text_result = "";

    for (int i = 0; i < n_segments; ++i)
    {
        const char *text = whisper_full_get_segment_text(g_ctx, i);
        text_result += std::string(text);
        
        if (!params.no_timestamps) {
            json jsonSegment;
            jsonSegment["from_ts"] = whisper_full_get_segment_t0(g_ctx, i);
            jsonSegment["to_ts"] = whisper_full_get_segment_t1(g_ctx, i);
            jsonSegment["text"] = text;
            segmentsJson.push_back(jsonSegment);
        }
    }

    if (!params.no_timestamps) {
        jsonResult["segments"] = segmentsJson;
    }
    
    jsonResult["text"] = text_result;
    return jsonResult;
}

extern "C"
{
    FUNCTION_ATTRIBUTE char *request(char *body)
    {
        try {
            json jsonBody = json::parse(body);
            if (jsonBody["@type"] == "abort") {
                g_should_abort.store(true);
                return jsonToChar({{"@type", "abort"}, {"message", "abort signal sent"}});
            }
            if (jsonBody["@type"] == "dispose") {
                std::lock_guard<std::mutex> lock(g_mutex);
                dispose_context_locked();
                return jsonToChar({{"@type", "dispose"}, {"message", "whisper context disposed"}});
            }
            if (jsonBody["@type"] == "getTextFromWavFile") {
                return jsonToChar(transcribe(jsonBody));
            }
            if (jsonBody["@type"] == "getVersion") {
                return jsonToChar({{"@type", "version"}, {"message", "lib v1.8.3-accel"}});
            }
            return jsonToChar({{"@type", "error"}, {"message", "method not found"}});
        } catch (const std::exception &e) {
            return jsonToChar({{"@type", "error"}, {"message", e.what()}});
        }
    }

    FUNCTION_ATTRIBUTE void free_string(char *ptr)
    {
        delete[] ptr;
    }

    // FORK: current transcription progress, 0-100. Safe to call from any
    // isolate at any time -- it reads an atomic and never blocks on the
    // mutex held by an in-flight transcribe().
    FUNCTION_ATTRIBUTE int get_progress()
    {
        return g_progress.load();
    }
}
