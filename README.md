# NEXUS Musik für iPhone

Ein nativer SwiftUI-Prototyp mit lokaler Audiomediathek, Dateiimport und Deezer-Katalogsuche mit Hörproben. Die Suche benötigt Internet; ein eigener Server ist nicht erforderlich. Die Benutzeroberfläche verwendet Deutsch oder Englisch entsprechend der iPhone-Sprache.

**Noch nicht implementiert:** Deezer-ARL-Anmeldung, vollständige Downloads, Import der NEXUS-Datenbank, Playlists und weitere Funktionen der Python-Anwendung. Die hochgeladene Datenbank und Sitzungsdatei sind absichtlich nicht Bestandteil des Repositorys.

## Build

GitHub Actions erstellt eine unsignierte IPA. Sie muss vor der Installation mit einem gültigen Zertifikat und Profil signiert werden. Lokal: Xcode 26 und XcodeGen installieren, `xcodegen generate` ausführen und das Projekt in Xcode öffnen. Mindestversion iOS 26.
