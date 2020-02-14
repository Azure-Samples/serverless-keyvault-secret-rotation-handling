using System;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;

namespace SampleFunctions
{
    public static class Logger
    {
        [FunctionName(nameof(Timer5sec))]
        public static void Timer5sec(
            [TimerTrigger(@"*/5 * * * * *")] TimerInfo _,
            ILogger log)
        {
            log.LogInformation($@"Logging an event at {DateTime.UtcNow}");
        }
    }
}
