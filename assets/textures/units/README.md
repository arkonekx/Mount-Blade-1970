# Tekstury sprzętu (grafika AI)

Materiały żołnierzy i pojazdów w bitwie 3D (`scripts/battle/battle_view.gd`).

## Pliki

```
assets/textures/units/<klucz>.png   256×256 — albedo materiału bryły
```

| klucz | powierzchnia | trafia na |
| --- | --- | --- |
| `uniform` | tkanina munduru: splot, szew, kieszeń, pas | kapsuła piechura |
| `armor` | blacha pancerza: spoiny, nity, właz, odpryski farby | kadłub, wieża pojazdu |
| `track` | ogniwa gąsienicy z zębami prowadzącymi | gąsienice i koła pojazdów |

Klucze są zgodne z `GameTextures.UNIT_KEYS` w `scripts/logic/game_textures.gd`
i z `tools/art/process_units.py`.

## Dlaczego tekstury są jasne i neutralne

W grze materiał dostaje **kolor strony** jako `albedo_color`, a Godot mnoży ten
kolor przez teksturę. Dlatego obie tekstury mają średnią jasnego, lekko
zielonkawego beżu (`#BFB6AB` i `#B0B2AB`), a nie własny kolor sprzętu:

* detal (splot, nity, przetarcia) pochodzi z tekstury,
* przynależność do strony (zielony gracz, niebiescy sojusznicy, czerwony wróg)
  pozostaje czytelna na pierwszy rzut oka,
* ta sama tekstura obsługuje obie strony konfliktu — nie trzeba dwóch kompletów.

Podgląd wszystkich trzech barw jest w `arkusz_jednostek.png`
z `tools/art/preview_textures.py`.

## Dopasowanie i odtworzenie

Pipeline jak dla terenu i otoczenia (`tools/art/pipeline.py`):

```bash
pip install pillow
python3 tools/art/process_units.py --raw /tmp/art/raw_units
python3 tools/art/preview_textures.py --out /tmp/art/out
```

## Prompty

Wspólny koniec promptu: *Flat surface, hand-painted matte style, soft painterly
brushwork, even diffuse lighting, no text, no letters, no numbers, no border,
no frame, fills the whole square edge to edge.*

| klucz | treść promptu |
| --- | --- |
| `uniform` | Seamless tileable texture of military fatigue fabric for a stylized 1970s Cold War game: coarse woven cotton-nylon cloth with subtle weave, a stitched seam, a small pouch flap and a strip of strap webbing crossing the surface, neutral light olive-grey so it can be tinted by a faction colour |
| `armor` | Seamless tileable texture of painted armoured vehicle steel for a stylized 1970s Cold War game: welded steel plate with panel seams, a row of bolt heads, a small hatch rim, chipped paint and faint grime, neutral grey-green so it can be tinted by a faction colour |
| `track` | Seamless tileable texture of a tank track run for a stylized 1970s Cold War game: steel track links with cleats, guide teeth and worn running surface, dust in the gaps, dark neutral steel-grey so it can be tinted by a faction colour |

## Sylwetki

`scripts/battle/battle_view.gd` składa pojazdy z brył: czołg ma 16 brył (kadłub,
dwie gąsienice, pięć kół, wieżę, właz, lufę), a wóz bojowy 13 (gąsienice, cztery
koła, wieżyczkę, lufę). Koła to walce obrócone osią w Z, więc toczą się
w kierunku marszu (+X). Materiały: `armor` na kadłub i wieżę, `track` na
gąsienice i koła, oba w barwie strony.

Podgląd brył z wymiarami: `makieta_pojazdow.png` z `tools/art/preview_textures.py`.

## Do zrobienia

Kształty są kanciaste (bryły, nie siatki) — osobny etap: modele siatkowe
(gąsienice, koła, lufa) albo gotowe assety 3D.
