# The House of the Dead · Scarlet Dawn PC

## Installera

1. Hämta **ScarletDawn-Local-Builder** som ZIP från [GitHub Releases](https://github.com/davidptrssvea/HOTD-Scarlet-Dawn-recomp/releases/latest) och packa upp.
2. Kör **Setup.cmd** och välj din egen uppackade **Scarlet Dawn (2018) Export**. Du kan välja dumpens huvudmapp eller **WindowsNoEditor**.
3. Öppna **ScarletDawn-PC → Play Scarlet Dawn.exe** när installationen är klar.

Du behöver Windows 10 eller 11 (64 bitar) och plats för en lokal kopia av spelet. Paketet innehåller startaren och kompatibilitetskod. Setup använder den befintliga Windows-versionen av spelet direkt, utan TeknoParrot eller JVSCD. Den stödda spelbinären har SHA-256 `0FDB745DBEA0E26521B1A624D9C289079B713EADE4842360CA36576E7C1E5AC0`.

Du kan också ange **-DumpPath** och **-InstallDir** till **setup.ps1**. Om den stödda spelkopian redan finns under **Game** i målmappen kan Setup installera programfilerna där.

## Spelbibliotek

Öppna **Game Library** i huvudmenyn för att välja mellan installerade exemplar av HOTD4, HOTD4 Special, HOTD EX och Scarlet Dawn. **Play** startar spelet med sparade inställningar, **Settings** öppnar spelets inställningar och **Menu** öppnar spelets vanliga startmeny. Använd **Locate installed game...** om en befintlig installation saknas.

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

**Apply stereo sound fix** använder vår verifierade stereopatch och dess matchande ACF-filer från din egen dump eller spelmapp. Setup importerar dem automatiskt även till en befintlig installation och sparar sökvägen till den valda dumpen. Vid spelstart letar startaren också efter filer som har lagts i **Game** efter installationen, samt i den sparade dumpen. De hashverifierade filerna lagras i **Local/Audio**; ingen manuell kopiering dit behövs. Originaldumpen ändras inte.

När stereofixen aktiveras används den matchande stereokonfigurationen tillsammans med tvåkanalig CRI/WASAPI. När den stängs av återställs den verifierade originalkonfigurationen och endast vår hanterade stereo-PAK tas bort ur spelkopians Paks-mapp. Originalet kan hämtas från en originaldump eller en kvarvarande **NewProject.acf.original** / **NewProject.acf.previous**. Okända patchvarianter avvisas. Om en del av paret saknas kan startaren inte skapa den: lägg våra verifierade filer i dumpen eller spelmappen och prova igen. Inga spel- eller ljudassets följer med paketet eller laddas ned av importen. Valet tillämpas nästa gång spelet startas.

## Spelstyrning

- Tryck **1** eller **Enter** för att starta som spelare 1.
- Sikta med musen och skjut med vänster musknapp. Höger musknapp växlar mellan tillgängliga vapen.
- **Input Test** visar pekarrörelser och knapptryck i Windows. En ljuspistol i musläge använder samma pekaringång. Fysisk kalibrering återstår.

Menyerna räknar om pekarens position till den plats rutorna använder i sitt UI. Startaren skapar en verifierad, lokalt korrigerad spelkopia för detta. Den tidigare ljudpatchen kan fortfarande väljas i menyn.

Startaren fyller i saknade standardbindningar i **Local/Profile/Saved/Config/WindowsNoEditor/Input.ini** och behåller befintliga bindningar.

### Sikten

Under **Settings → Controls → Crosshair** kan du välja Original, Off, Dot, Cross, Ring, Ring + dot eller Open cross. De egna siktena stöder tre storlekar och fem färger. Vid tvåspelarläge får spelare 2 automatiskt en kontrasterande färg. Siktet följer musen eller den tilldelade ljuspistolen under spel och döljs utanför spelytan.

## Handkontroll

Välj **Gamepad (XInput)** under **Settings → Controls** och spara. Läget stöder Xbox-kompatibla XInput-handkontroller och tilldelar upp till två handkontroller automatiskt. Tryck **Menu / Start** på din handkontroll för att gå med.

- **Vänster eller höger spak** siktar.
- **RT** eller **A** skjuter och väljer i spelets menyer.
- **X** eller **LB** laddar om.
- **Y** eller **RB** byter vapen.

Med siktet **Original** visar handkontrollsläget en ring med punkt. Du kan välja ett annat sikte eller stänga av det under **Crosshair**.

## Paus

Tryck **Esc** eller **View / Back** på handkontrollen för att pausa. Välj **Resume** för att fortsätta eller **Settings** för att öppna inställningarna. Du kan navigera i pausmenyn med styrkorset och välja med **A**. Siktesinställningar och **Gamepad aim speed** börjar gälla när du fortsätter. Övriga inställningar börjar gälla nästa gång du startar spelet.

## Sinden och andra ljuspistoler

Under **Settings → Controls** kan du också välja mus eller ljuspistol.

- **Mouse** använder den vanliga musstyrningen.
- **Sinden (Windows mouse)** använder pekaren från Sinden-programvaran för spelare 1. Starta och kalibrera pistolen i Sinden-programvaran. Använd vänster musknapp för avtryckaren på skärmen och höger musknapp för avtryckaren utanför skärmen i Sinden-programvaran.
- **Lightgun (Raw Input)** läser en separat Windows-enhet per spelare. **Auto** tilldelar absoluta enheter i den ordning de används. Välj en bestämd enhet för fast spelarordning. Spelare 2 är avstängd tills du väljer en enhet eller **Auto** för den platsen.

Vit **Sinden border** visas runt spelytan. Tjockleken kan ställas från 0,75 till 3 procent. Välj **Off** om en annan ram redan visas.

Med **Off-screen reload** aktiverat laddar spelet om när siktet rapporteras utanför spelytan. Läget tar också emot den högra musknapp som många ljuspistoler skickar när avtryckaren trycks utanför skärmen. Musens mittenknapp eller första sidoknapp växlar vapen i ljuspistollägena. Tryck **1 / Enter** för spelare 1 och **2** för en konfigurerad Raw Input-spelare 2. Den andra sidoknappen kan också starta respektive spelare.

I Sinden-läget kan du även slå på **Switch weapon on reload if an extra weapon has ammo**. Omladdningsrörelsen och pistolens högerklick växlar då vapen när ett extravapen har ammunition. När extravapnen är tomma eller saknas laddas standardvapnet om.

## Testat i spelet

Ett dolt speltest gick från attract-läget via spelarinträde och banval till första banan, med TeknoParrot och JVSCD avstängda. I Items följde markeringen pekaren mellan Machine Gun EX och Energy Cannon vid 1280 × 720. Klick valde båda rutorna. Machine Gun EX markerades och valdes även vid 1920 × 1080. Avfyrning verifierades på första banan efter menyfixen. Performance-profilen började rendera i 960 × 540 med en texturpool på 512 MB. Spelet använder även vissa egna renderingsmål i 1920 × 1080 när banan laddas.

Stereopatchen monterades under speltestet. Ljudutmatningen var avstängd, så patchens hörbara resultat ingick inte i testet.
