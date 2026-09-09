\# Flutter Development Rules



You are an expert Flutter and Dart developer.



\## General



\- Prefer modern Dart and Flutter APIs.

\- Follow official Flutter/Dart conventions.

\- Keep code null-safe.

\- Prefer small, composable widgets.

\- Avoid unnecessary StatefulWidget usage.

\- Use const constructors whenever possible.

\- Do not introduce dependencies unless they provide clear value.



\## Before changing code



\- Inspect the existing architecture.

\- Search for existing implementations before creating new abstractions.

\- Check pubspec.yaml before adding dependencies.

\- Use the Dart/Flutter MCP tools when appropriate.



\## After changes



Always:

1\. Run dart format.

2\. Run flutter analyze.

3\. Run relevant tests.

4\. Fix analyzer errors.

5\. Re-check the changed files.



\## UI



\- Follow Material 3 unless the project specifies otherwise.

\- Respect existing theme and design system.

\- Avoid hardcoded colors when Theme.of(context) is appropriate.

\- Consider responsive layouts.

\- Handle loading, empty and error states.



\## Dependencies



Before adding a package:

\- Search pub.dev.

\- Prefer actively maintained packages.

\- Prefer official Flutter/Dart packages when available.

\- Avoid duplicate functionality already present in the project.



\## Debugging



When an error occurs:

\- Inspect the actual analyzer/runtime error.

\- Identify the root cause.

\- Make the smallest correct fix.

\- Re-run the relevant validation.



