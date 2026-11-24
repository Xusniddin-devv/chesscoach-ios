// C bridge that runs Stockfish's UCI loop in-process (GPLv3, like the engine it wraps).
//
// Stockfish reads commands with getline(std::cin) and writes with std::cout. While the
// engine runs, std::cin reads from a blocking line queue fed by sf_send, and std::cout
// writes into a streambuf that splits on '\n' and hands each line to the callback.

#include "stockfish_bridge.h"

#include <condition_variable>
#include <deque>
#include <iostream>
#include <memory>
#include <mutex>
#include <streambuf>
#include <string>

#include "stockfish/bitboard.h"
#include "stockfish/misc.h"
#include "stockfish/position.h"
#include "stockfish/thread_win32_osx.h"
#include "stockfish/uci.h"

namespace {

// Stockfish keeps UCIEngine::engine private, but sf_quit needs Engine::stop() to end a
// search that a blocking command (ucinewgame, go, setoption Hash...) is waiting on.
// Explicit template instantiation may name private members, so this reaches it legally.
Stockfish::Engine& engine_of(Stockfish::UCIEngine& uci);

template<Stockfish::Engine Stockfish::UCIEngine::*Member>
struct EngineAccess {
    friend Stockfish::Engine& engine_of(Stockfish::UCIEngine& uci) { return uci.*Member; }
};

template struct EngineAccess<&Stockfish::UCIEngine::engine>;

// std::cin replacement: underflow blocks until sf_send enqueues a line.
class LineQueueBuf: public std::streambuf {
   public:
    void push(std::string line) {
        {
            std::lock_guard<std::mutex> lock(mutex);
            lines.push_back(std::move(line) + '\n');
        }
        ready.notify_one();
    }

    // Drops unread commands and leaves `line` as the only one.
    void replace_all(std::string line) {
        {
            std::lock_guard<std::mutex> lock(mutex);
            lines.clear();
            lines.push_back(std::move(line) + '\n');
        }
        ready.notify_one();
    }

    void reset() {
        std::lock_guard<std::mutex> lock(mutex);
        lines.clear();
        current.clear();
        setg(nullptr, nullptr, nullptr);
    }

   protected:
    int_type underflow() override {
        std::unique_lock<std::mutex> lock(mutex);
        ready.wait(lock, [this] { return !lines.empty(); });
        current = std::move(lines.front());
        lines.pop_front();
        char* begin = current.data();
        setg(begin, begin, begin + current.size());
        return traits_type::to_int_type(*gptr());
    }

   private:
    std::mutex              mutex;
    std::condition_variable ready;
    std::deque<std::string> lines;
    std::string             current;
};

// std::cout replacement: buffers characters and emits each complete line to the callback.
class CallbackLineBuf: public std::streambuf {
   public:
    void set_callback(sf_line_callback cb, void* ctx) {
        std::lock_guard<std::mutex> lock(mutex);
        callback = cb;
        context  = ctx;
        pending.clear();
    }

   protected:
    int_type overflow(int_type ch) override {
        if (traits_type::eq_int_type(ch, traits_type::eof()))
            return traits_type::not_eof(ch);
        char c = traits_type::to_char_type(ch);
        xsputn(&c, 1);
        return ch;
    }

    std::streamsize xsputn(const char* s, std::streamsize n) override {
        std::lock_guard<std::mutex> lock(mutex);
        for (std::streamsize i = 0; i < n; ++i)
        {
            if (s[i] != '\n')
            {
                pending.push_back(s[i]);
                continue;
            }
            if (!pending.empty() && pending.back() == '\r')
                pending.pop_back();
            if (callback)
                callback(pending.c_str(), context);
            pending.clear();
        }
        return n;
    }

   private:
    std::mutex       mutex;
    sf_line_callback callback = nullptr;
    void*            context  = nullptr;
    std::string      pending;
};

LineQueueBuf    inputBuf;
CallbackLineBuf outputBuf;

std::mutex                   lifecycleMutex;
// Stockfish's NativeThread gives the UCI thread an 8 MB stack (Apple defaults to 512 KB).
std::unique_ptr<Stockfish::NativeThread> engineThread;
std::streambuf*              savedCin  = nullptr;
std::streambuf*              savedCout = nullptr;

// The live engine, set while the UCI loop runs. Guarded by engineMutex so sf_quit can
// call stop() without racing the engine's destruction.
std::mutex         engineMutex;
Stockfish::Engine* runningEngine = nullptr;

void run_uci_loop() {
    using namespace Stockfish;

    // Mirrors Stockfish's main(); the banner line it prints first is not part of UCI.
    static std::once_flag initOnce;
    std::call_once(initOnce, [] {
        Bitboards::init();
        Position::init();
    });

    char  name[] = "stockfish";
    char* argv[] = {name, nullptr};
    auto  uci    = std::make_unique<UCIEngine>(1, argv);
    {
        std::lock_guard<std::mutex> lock(engineMutex);
        runningEngine = &engine_of(*uci);
    }
    uci->loop();
    {
        std::lock_guard<std::mutex> lock(engineMutex);
        runningEngine = nullptr;
    }
}

}  // namespace

extern "C" {

void sf_start(sf_line_callback cb, void* ctx) {
    std::lock_guard<std::mutex> lock(lifecycleMutex);
    if (engineThread)
        return;

    inputBuf.reset();
    outputBuf.set_callback(cb, ctx);
    savedCin  = std::cin.rdbuf(&inputBuf);
    savedCout = std::cout.rdbuf(&outputBuf);

    engineThread = std::make_unique<Stockfish::NativeThread>(run_uci_loop);
}

void sf_send(const char* command) {
    if (command)
        inputBuf.push(command);
}

void sf_quit(void) {
    std::lock_guard<std::mutex> lock(lifecycleMutex);
    if (!engineThread)
        return;

    {
        // Stop first: the UCI thread may be blocked in a command that waits for the search,
        // in which case a queued `quit` alone would never be read. Commands still queued are
        // dropped so none of them can start or wait on another search before `quit`.
        // The engine cannot be destroyed meanwhile: that needs `quit`, which is pushed here.
        std::lock_guard<std::mutex> lock(engineMutex);
        if (runningEngine)
            runningEngine->stop();
        inputBuf.replace_all("quit");
    }
    engineThread->join();
    engineThread.reset();

    std::cin.rdbuf(savedCin);
    std::cout.rdbuf(savedCout);
    std::cin.clear();
    std::cout.clear();
    outputBuf.set_callback(nullptr, nullptr);
}

const char* sf_version(void) {
    static const std::string version = Stockfish::engine_version_info();
    return version.c_str();
}

}  // extern "C"
