// Test-only host for issue #17. It never falls back to an affirmative/default choice.
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;

namespace OSDStage.Tests.Issue17
{
    public sealed class DecliningHost : PSHost
    {
        private readonly Guid id = Guid.NewGuid();
        public readonly DecliningUI Interaction = new DecliningUI();
        public override Guid InstanceId { get { return id; } }
        public override string Name { get { return "OSDStage confirmation test"; } }
        public override Version Version { get { return new Version(1, 0); } }
        public override PSHostUserInterface UI { get { return Interaction; } }
        public override CultureInfo CurrentCulture { get { return CultureInfo.GetCultureInfo("en-US"); } }
        public override CultureInfo CurrentUICulture { get { return CultureInfo.GetCultureInfo("en-US"); } }
        public override void EnterNestedPrompt() { throw new InvalidOperationException("Unexpected nested prompt."); }
        public override void ExitNestedPrompt() { throw new InvalidOperationException("Unexpected nested prompt exit."); }
        public override void NotifyBeginApplication() { }
        public override void NotifyEndApplication() { }
        public override void SetShouldExit(int exitCode) { throw new InvalidOperationException("Unexpected host exit."); }
    }

    public sealed class DecliningUI : PSHostUserInterface
    {
        public readonly List<string> PromptMessages = new List<string>();
        public readonly List<string> SelectedChoices = new List<string>();
        public override PSHostRawUserInterface RawUI { get { return null; } }

        public override int PromptForChoice(string caption, string message,
            Collection<ChoiceDescription> choices, int defaultChoice)
        {
            PromptMessages.Add(message);
            for (int index = 0; index < choices.Count; index++)
            {
                string label = choices[index].Label.Replace("&", "").Trim();
                if (String.Equals(label, "No", StringComparison.OrdinalIgnoreCase))
                {
                    SelectedChoices.Add(label);
                    return index;
                }
            }
            // Fail, rather than accepting defaultChoice or assuming a stable index/localization.
            throw new InvalidOperationException("Expected an explicit No confirmation option.");
        }

        public override Dictionary<string, PSObject> Prompt(string caption, string message,
            Collection<FieldDescription> descriptions) { throw new InvalidOperationException("Unexpected input prompt."); }
        public override string ReadLine() { throw new InvalidOperationException("Unexpected console read."); }
        public override SecureString ReadLineAsSecureString() { throw new InvalidOperationException("Unexpected secure input."); }
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName)
        { throw new InvalidOperationException("Unexpected credential prompt."); }
        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName,
            PSCredentialTypes allowedCredentialTypes, PSCredentialUIOptions options)
        { throw new InvalidOperationException("Unexpected credential prompt."); }
        public override void Write(string value) { }
        public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value) { }
        public override void WriteLine(string value) { }
        public override void WriteErrorLine(string value) { }
        public override void WriteDebugLine(string message) { }
        public override void WriteVerboseLine(string message) { }
        public override void WriteWarningLine(string message) { }
        public override void WriteProgress(long sourceId, ProgressRecord record) { }
    }
}
