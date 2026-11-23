# The House of the Dead · Scarlet Dawn PC

## Installera

1. Hämta **ScarletDawn-Local-Builder** som ZIP från [GitHub Releases](https://github.com/davidptrssvea/HOTD-Scarlet-Dawn-recomp/releases/latest) och packa upp.
2. Kör **Setup.cmd** och välj din egen uppackade **Scarlet Dawn (2018) Export**. Du kan välja dumpens huvudmapp eller **WindowsNoEditor**.
3. Öppna **ScarletDawn-PC → Play Scarlet Dawn.exe** när installationen är klar.

Du behöver Windows 10 eller 11 (64 bitar) och plats för en lokal kopia av spelet. Paketet innehåller startaren och kompatibilitetskod. Setup använder den befintliga Windows-versionen av spelet direkt, utan TeknoParrot eller JVSCD. Den stödda spelbinären har SHA-256 `0FDB745DBEA0E26521B1A624D9C289079B713EADE4842360CA36576E7C1E5AC0`.

Du kan också ange **-DumpPath** och **-InstallDir** till **setup.ps1**. Om den stödda spelkopian redan finns under **Game** i målmappen kan Setup installera programfilerna där.

## Uppdateringar

**Updates** i huvudmenyn visar installerad version och senaste ändringar från GitHub. Välj **Download and install** om en nyare version finns. Startaren verifierar ZIP-filen innan den byter programfiler och öppnar menyn igen. **Game** och **Local** med inställningar, profiler och lokala ljudfiler finns kvar efter uppdateringen.

## Grafik

- **Performance** använder utmatning i 1280 × 720, 75 % renderingsskala och låg grafikkvalitet. Spelets logg visar en intern 3D-upplösning på 960 × 540 och en texturpool på 512 MB.
- **Balanced** använder 1600 × 900, 85 % renderingsskala och medelkvalitet.
- **Quality** använder 1920 × 1080, 100 % renderingsskala och högsta kvalitet.

Upplösning, renderingsskala, kvalitet, fönsterläge och VSync kan också väljas var för sig. Inställningarna används nästa gång du startar spelet.

### Advanced Settings

Öppna **Settings → Advanced Settings** för att finjustera grafiken. Fältet **Preset** följer den valda grafikkvaliteten. **Reset to preset values** återställer avancerade val. Ändringarna gäller nästa gång du startar spelet.

- **Frame rate limit** har 30, 45 och 60 FPS. Upplösning och renderingsskala finns på huvudsidan för grafik.
- **Dynamic shadows**, **Volumetric fog** och **Screen-space reflections** påverkar GPU-belastningen i scener som använder effekterna.
- **Texture detail** styr texturernas detaljnivå. **Texture pool** styr Unreal Engines budget för strömmade texturer.
- **Anti-aliasing**, **Ambient occlusion**, **Effects quality**, **Bloom**, **Depth of field** och **Motion blur** kan justeras var för sig.

## Ljud

**Apply stereo sound fix** använder din lokala stereopatch när den stödda patchfilen och ACF-filerna finns tillgängliga. Setup importerar dessa från dumpen om de matchar den kända stereofixen. Menyn använder stereopatchen och dess ACF-fil tillsammans med tvåkanalig CRI/WASAPI. Avmarkera valet för att återställa den lokala spelkopians ursprungliga ACF och ta bort den hanterade stereopatchen ur Paks-mappen. Valet tillämpas när spelet startas.

## Spelstyrning

- Tryck **1** eller **Enter** för att starta som spelare 1.
- Sikta med musen och skjut med vänster musknapp. Höger musknapp växlar mellan tillgängliga vapen.
- **Input Test** visar pekarrörelser och knapptryck i Windows. En ljuspistol i musläge använder samma pekaringång. Fysisk kalibrering återstår.

Menyerna räknar om pekarens position till den plats rutorna använder i sitt UI. Startaren skapar en verifierad, lokalt korrigerad spelkopia för detta. Den tidigare ljudpatchen kan fortfarande väljas i menyn.

Startaren fyller i saknade standardbindningar i **Local/Profile/Saved/Config/WindowsNoEditor/Input.ini** och behåller befintliga bindningar.

### Sikten

Under **Settings → Controls → Crosshair** kan du välja Original, Off, Dot, Cross, Ring, Ring + dot eller Open cross. De egna siktena stöder tre storlekar och fem färger. Vid tvåspelarläge får spelare 2 automatiskt en kontrasterande färg. Siktet följer musen eller den tilldelade ljuspistolen under spel och döljs utanför spelytan.

## Sinden och andra ljuspistoler

Under **Settings → Controls** finns tre inmatningslägen.

- **Mouse** använder den vanliga musstyrningen.
- **Sinden (Windows mouse)** använder pekaren från Sinden-programvaran för spelare 1. Starta och kalibrera pistolen i Sinden-programvaran. Använd vänster musknapp för avtryckaren på skärmen och höger musknapp för avtryckaren utanför skärmen i Sinden-programvaran.
- **Lightgun (Raw Input)** läser en separat Windows-enhet per spelare. **Auto** tilldelar absoluta enheter i den ordning de används. Välj en bestämd enhet för fast spelarordning. Spelare 2 är avstängd tills du väljer en enhet eller **Auto** för den platsen.

Vit **Sinden border** visas runt spelytan. Tjockleken kan ställas från 0,75 till 3 procent. Välj **Off** om en annan ram redan visas.

Med **Off-screen reload** aktiverat laddar spelet om när siktet rapporteras utanför spelytan. Läget tar också emot den högra musknapp som många ljuspistoler skickar när avtryckaren trycks utanför skärmen. Musens mittenknapp eller första sidoknapp växlar vapen i ljuspistollägena. Tryck **1 / Enter** för spelare 1 och **2** för en konfigurerad Raw Input-spelare 2. Den andra sidoknappen kan också starta respektive spelare.

## Testat i spelet

Ett dolt speltest gick från attract-läget via spelarinträde och banval till första banan, med TeknoParrot och JVSCD avstängda. I Items följde markeringen pekaren mellan Machine Gun EX och Energy Cannon vid 1280 × 720. Klick valde båda rutorna. Machine Gun EX markerades och valdes även vid 1920 × 1080. Avfyrning verifierades på första banan efter menyfixen. Performance-profilen började rendera i 960 × 540 med en texturpool på 512 MB. Spelet använder även vissa egna renderingsmål i 1920 × 1080 när banan laddas.

Stereopatchen monterades under speltestet. Ljudutmatningen var avstängd, så patchens hörbara resultat ingick inte i testet.
