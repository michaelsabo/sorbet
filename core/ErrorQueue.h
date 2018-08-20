#ifndef SORBET_ERROR_QUEUE_H
#define SORBET_ERROR_QUEUE_H

#include "ErrorFlusher.h"
#include "ErrorQueueMessage.h"

namespace sorbet {
namespace core {

class ErrorQueue {
private:
    virtual void checkOwned() = 0;
    virtual std::vector<std::unique_ptr<ErrorQueueMessage>> drainAll() = 0;
    virtual std::vector<std::unique_ptr<ErrorQueueMessage>> drainFlushed() = 0;
    ErrorFlusher errorFlusher;

public:
    spdlog::logger &logger;
    spdlog::logger &tracer;
    std::atomic<bool> hadCritical{false};
    std::atomic<int> errorCount{0};
    bool ignoreFlushes{false};

    ErrorQueue(spdlog::logger &logger, spdlog::logger &tracer);
    virtual ~ErrorQueue();

    /** register a new error to be reported */
    virtual void pushError(const GlobalState &gs, std::unique_ptr<BasicError> error) = 0;
    virtual void pushQueryResponse(std::unique_ptr<QueryResponse> error) = 0;
    /** indicate that errors for `file` should be flushed on next call to to flushErrors */
    virtual void markFileForFlushing(FileRef file) = 0;
    /** Extract all query responses. This discards all errors currently present in error Queue */
    std::vector<std::unique_ptr<core::QueryResponse>> drainQueryResponses();
    /** Extract all errors. This discards all query responses currently present in error Queue */
    std::vector<std::unique_ptr<core::BasicError>> drainAllErrors();

    void flushErrors(bool all = false);
    void flushErrorCount();
    void flushAutocorrects(const GlobalState &gs);
};

} // namespace core
} // namespace sorbet

#endif