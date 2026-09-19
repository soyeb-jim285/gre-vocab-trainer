import json, sys

def w(parts, literal, path, cousins, confidence, transparent, charge):
    return {
        "parts": [{"piece": p, "origin": o, "meaning": m} for (p, o, m) in parts],
        "literal": literal,
        "path": path,
        "cousins": cousins,
        "confidence": confidence,
        "transparent": transparent,
        "charge": charge,
    }

DATA = {}

DATA["slay"] = w(
    [("slean", "Old English", "to strike, smite")],
    "to strike down",
    "Slay comes from Old English slean, to strike or smite, the same root as slaughter. It narrowed to mean killing, especially by violent striking.",
    ["slaughter"], "high", True, "negative")

DATA["sleight"] = w(
    [("slaegr", "Old Norse", "cunning, sly")],
    "cunning, cleverness",
    "Sleight comes from Old Norse slœgth, cleverness or cunning, from slœgr, sly. Sleight of hand names skillful, cunning trickery performed manually, as in conjuring.",
    ["sly"], "high", True, "neutral")

DATA["slew"] = w(
    [("sluagh", "Irish", "host, crowd, multitude")],
    "a host, a crowd",
    "Slew comes from Irish Gaelic sluagh, a host or multitude, borrowed into American English. It kept the sense of a great crowd or number of things.",
    [], "high", True, "neutral")

DATA["slight"] = w(
    [("slettr", "Old Norse", "smooth, level, flat")],
    "smooth, flat, of little substance",
    "Slight comes from Old Norse slettr, smooth or level, which shifted to mean thin, slim, trifling in substance. To slight someone is to treat them as if they were of little substance, insulting them through neglect.",
    [], "medium", True, "negative")

DATA["slothful"] = w(
    [("slaw", "Old English", "slow")],
    "full of slowness",
    "Sloth comes from Old English slawth, slowness, from slaw, slow. Slothful describes someone marked by that slowness of will and action, lazy and averse to effort.",
    ["slow"], "high", True, "negative")

DATA["slovenly"] = w(
    [("sloveyn", "Middle English", "an untidy, negligent person; origin somewhat uncertain")],
    "in the manner of an untidy, negligent person",
    "Slovenly comes from sloven, a Middle English word for a habitually untidy person, likely related to a Flemish or Dutch word for careless and dirty. It describes a careless, unkempt manner.",
    [], "medium", True, "negative")

DATA["sluggish"] = w(
    [("slugge", "Middle English", "a lazy, slow-moving person; Scandinavian origin")],
    "like a slug, a slow lazy creature",
    "Sluggish comes from slug, a Middle English word for a lazy, slow-moving person, of Scandinavian origin. It describes movement or energy that drags, slow and lacking vigor.",
    [], "medium", True, "negative")

DATA["sluice"] = w(
    [("ex-", "Latin", "out"), ("claudere", "Latin", "to shut, close")],
    "shut out (water), a floodgate",
    "Sluice comes from Latin exclusa aqua, water shut out, from excludere, to shut out, from claudere, to close. A sluice gate controls the shutting out or release of water, and to sluice is to wash with that controlled rush.",
    ["exclude", "close", "conclude"], "high", True, "neutral")

DATA["smattering"] = w(
    [("smateren", "Middle English", "to talk superficially; imitative origin")],
    "a light chattering, superficial talk",
    "Smattering comes from smatter, to talk about something superficially without real knowledge, likely an imitative word for light chatter. It names a small, surface-level amount of knowledge or quantity.",
    [], "low", True, "neutral")

DATA["smug"] = w(
    [("smuk", "Low German", "neat, trim, smart")],
    "neat, trim, spruce",
    "Smug comes from a Low German word meaning neat or trim in appearance. The word shifted from praising tidy self-presentation to criticizing the self-satisfied complacency that often goes with it.",
    [], "medium", False, "negative")

DATA["snide"] = w(
    [("snide", "English", "uncertain origin, originally slang for counterfeit")],
    "unknown, originally meant counterfeit or sham",
    "Snide first appeared as slang for something counterfeit or sham, its deeper origin uncertain, perhaps linked to a German word for cutting. It shifted to describe remarks that are slyly, cuttingly disparaging.",
    [], "low", False, "negative")

DATA["snub"] = w(
    [("snubba", "Old Norse", "to chide, check sharply")],
    "to check sharply, cut short",
    "Snub comes from Old Norse snubba, to check or rebuke sharply. To snub someone is to cut them off sharply with deliberate coldness, insulting them by that rebuff.",
    [], "medium", True, "negative")

DATA["sob"] = w(
    [("sob", "English", "imitative of a gasping sound")],
    "imitative of a gasping sound",
    "Sob is likely imitative, echoing the catching, gasping sound itself. It has always meant weeping with audible, convulsive gasps.",
    [], "low", True, "negative")

DATA["sobriquet"] = w(
    [("sobriquet", "French", "originally a chuck under the chin; origin uncertain")],
    "a chuck under the chin",
    "French sobriquet originally meant a playful tap under the chin, its exact origin unclear. The word shifted from that gesture to a playful or mocking name given to someone, a nickname.",
    [], "low", False, "neutral")

DATA["solecism"] = w(
    [("Soloi", "Greek", "proper name, a colony whose dialect was considered corrupt")],
    "speaking like the people of Soloi",
    "Greek soloikismos, incorrect speech, was said to derive from Soloi, an Athenian colony whose settlers were mocked for speaking a debased Greek dialect. Solecism kept that sense of a grammatical error, and extended to any social blunder.",
    [], "medium", True, "negative")

DATA["solicitous"] = w(
    [("sollus", "Latin", "whole, entire"), ("ciere", "Latin", "to stir, move")],
    "wholly stirred up, thoroughly agitated",
    "Latin sollicitus meant thoroughly stirred up or agitated, from sollus, whole, and ciere, to move. Solicitous kept the sense of being anxiously stirred on someone's behalf, showing worried, attentive care.",
    ["incite", "excite"], "high", True, "positive")

DATA["solicitude"] = w(
    [("sollus", "Latin", "whole"), ("ciere", "Latin", "to stir, move")],
    "a state of being wholly stirred up",
    "From the same Latin sollicitus as solicitous, solicitude names the state of anxious, attentive concern felt on someone's behalf.",
    ["incite", "excite"], "high", True, "positive")

DATA["solidarity"] = w(
    [("solidus", "Latin", "solid, whole")],
    "solidness, wholeness together",
    "Solidarity comes from French solidaire, interdependent, from Latin solidus, solid or whole. It names the unity people feel when standing together, solid as one body, over shared interests.",
    ["solid", "consolidate"], "high", True, "positive")

DATA["soliloquy"] = w(
    [("solus", "Latin", "alone"), ("loqui", "Latin", "to speak")],
    "speaking alone",
    "Soliloquy joins Latin solus, alone, with loqui, to speak. It names a speech given alone, typically on stage, revealing a character's private thoughts aloud.",
    ["solo", "loquacious", "eloquent", "colloquial"], "high", True, "neutral")

DATA["solvent"] = w(
    [("solvere", "Latin", "to loosen, pay off")],
    "loosening, paying off a debt",
    "Latin solvere meant to loosen or untie, and by extension to pay off a debt, releasing oneself from an obligation. Solvent describes someone who can loosen, or pay off, all their debts.",
    ["solve", "dissolve", "resolve"], "high", True, "positive")

DATA["somatic"] = w(
    [("soma", "Greek", "body")],
    "of the body",
    "Greek soma, body, gives somatic its plain sense: relating to the physical body, as opposed to the mind.",
    ["psychosomatic"], "high", True, "neutral")

DATA["somber"] = w(
    [("sub-", "Latin", "under"), ("umbra", "Latin", "shade, shadow")],
    "under the shade, shadowed",
    "French sombre traces to Vulgar Latin subumbrare, to put in shade, from sub-, under, and umbra, shadow. Somber kept that image of being cast in shadow, dark and gloomy in tone.",
    ["umbrella", "penumbra", "adumbrate"], "high", True, "negative")

DATA["somnolent"] = w(
    [("somnus", "Latin", "sleep")],
    "full of sleep",
    "Latin somnolentus, from somnus, sleep, meant drowsy or sleepy. Somnolent kept that sense, describing a sleepy state or something that induces one.",
    ["insomnia"], "high", True, "neutral")

DATA["sonorous"] = w(
    [("sonare", "Latin", "to sound")],
    "full of sound",
    "Latin sonorus, from sonare, to sound, described a full, resounding sound. Sonorous kept that sense of deep, rich resonance, of voice or tone.",
    ["sonic", "resonant", "unison"], "high", True, "positive")

DATA["sophisticated"] = w(
    [("sophos", "Greek", "wise, clever")],
    "made clever, tampered with cleverly",
    "Sophisticated traces to Greek sophos, wise or clever, via sophist, one who argues cleverly. The word first meant adulterated or falsified through clever tampering, and only in modern use shifted to mean refined, complex, and worldly.",
    ["sophist", "philosophy"], "high", False, "positive")

DATA["sophistry"] = w(
    [("sophos", "Greek", "wise, clever")],
    "the practice of a sophist, a clever arguer",
    "From the same Greek sophos, wise, as sophisticated, sophistry names the sophist's trade: reasoning that is clever and persuasive in form but false or misleading in substance.",
    ["sophisticated", "philosophy"], "high", True, "negative")

DATA["soporific"] = w(
    [("sopor", "Latin", "deep sleep"), ("facere", "Latin", "to make")],
    "making deep sleep",
    "Soporific combines Latin sopor, deep sleep, with facere, to make. It describes anything that makes one sleepy, from a dull lecture to a drug.",
    ["fact", "factory", "manufacture"], "high", True, "negative")

DATA["sordid"] = w(
    [("sordere", "Latin", "to be dirty, filthy")],
    "dirty, filthy",
    "Latin sordidus, from sordere, to be dirty, described literal filth and, by extension, moral baseness. Sordid kept both threads: physically dirty and morally squalid.",
    [], "high", True, "negative")

DATA["sound"] = w(
    [("gesund", "Old English", "healthy, whole, safe")],
    "healthy, whole",
    "Sound in this sense comes from Old English gesund, healthy and whole, the same root as the German greeting gesund. It describes something whole and healthy in condition, reliable and free of defect.",
    [], "high", True, "positive")

DATA["spangle"] = w(
    [("spang", "Germanic", "a small shining metal ornament or clasp")],
    "a small shining ornament",
    "Spangle is a diminutive of spang, a Germanic word for a small shining metal ornament or clasp. To spangle something is to scatter it with such small glittering pieces.",
    [], "medium", True, "neutral")

DATA["sparing"] = w(
    [("sparian", "Old English", "to refrain from, be frugal")],
    "holding back, being frugal",
    "Sparing comes from Old English sparian, to hold back or be frugal with something. It describes using something economically, in small, careful amounts.",
    ["spare"], "high", True, "neutral")

DATA["sparse"] = w(
    [("spargere", "Latin", "to scatter, strew")],
    "scattered",
    "Latin spargere meant to scatter or strew about. Sparse kept that image, describing things scattered so thinly that little remains in any one place.",
    ["disperse", "aspersion"], "high", True, "neutral")

DATA["spartan"] = w(
    [("Sparta", "Greek", "proper name, the city-state known for austere discipline")],
    "in the manner of Sparta",
    "Spartan comes from Sparta, the ancient Greek city famed for training its citizens to a life of rigorous discipline and austere simplicity. Spartan describes any severely plain, unadorned way of living.",
    [], "high", True, "neutral")

DATA["spat"] = w(
    [("spat", "English", "uncertain, possibly imitative")],
    "unknown, possibly an imitative slapping sound",
    "Spat, meaning a petty quarrel, is of uncertain origin, possibly echoing the sound of a slap or spatter. It names a brief, minor squabble.",
    [], "low", False, "negative")

DATA["spate"] = w(
    [("spate", "Middle English", "sudden flood; origin uncertain")],
    "a sudden flood",
    "Spate first meant a sudden flood or rush of water, especially in rivers after heavy rain, its exact origin unclear. It extended metaphorically to any sudden rush or large number of things occurring at once.",
    [], "low", True, "neutral")

DATA["spearhead"] = w(
    [("spere", "Old English", "spear"), ("heafod", "Old English", "head")],
    "the point of a spear",
    "A spearhead is literally the pointed tip of a spear, the part that leads the thrust. To spearhead an effort is to take that leading position, driving the attack or initiative forward.",
    [], "high", True, "neutral")

DATA["specious"] = w(
    [("species", "Latin", "appearance, form"), ("specere", "Latin", "to look, see")],
    "good in appearance",
    "Latin speciosus meant good-looking or showy, from species, appearance, and specere, to look. The word shifted from praising a fine appearance to criticizing an argument that merely looks right, plausible on the surface but actually false.",
    ["spectator", "inspect", "perspective"], "high", True, "negative")

DATA["spectral"] = w(
    [("specere", "Latin", "to look, see")],
    "of an apparition, a seen image",
    "Latin spectrum, from specere, to look, named an appearance or apparition, the visual image of a ghost. Spectral kept that ghostly, apparition-like sense.",
    ["spectator", "inspect", "spectrum"], "high", True, "negative")

DATA["spectrum"] = w(
    [("specere", "Latin", "to look, see")],
    "an appearance, an image seen",
    "Latin spectrum, an appearance or image, from specere, to look, was applied by Newton to the band of colors produced when light is refracted. Spectrum broadened from that visual band to any full range of related qualities.",
    ["spectator", "inspect", "spectral"], "high", True, "neutral")

DATA["speculate"] = w(
    [("specere", "Latin", "to look, see"), ("specula", "Latin", "watchtower")],
    "to watch from a lookout tower",
    "Latin speculari meant to watch or observe from a lookout, specula, a watchtower. Speculate kept the sense of looking ahead without certainty, whether guessing at unproven ideas or investing money on an uncertain outcome.",
    ["spectator", "inspect", "spectacle"], "high", True, "neutral")

DATA["spendthrift"] = w(
    [("spendan", "Old English", "to spend, pay out, from Latin expendere"), ("thrift", "Old Norse", "prosperity, savings, from thrive")],
    "one who spends away their savings",
    "Spendthrift joins spend, ultimately from Latin expendere, to pay out, with thrift, meaning savings or prosperity, from thrive. A spendthrift is literally someone who spends away their thrift, squandering what should have been saved.",
    ["expend", "thrive"], "high", True, "negative")

DATA["splenetic"] = w(
    [("splen", "Greek", "spleen")],
    "of the spleen",
    "Greek splen, spleen, named the organ ancient and medieval physiology believed to be the seat of irritability and bad temper. Splenetic kept that association: someone splenetic is peevish and spiteful, as if governed by an ill-tempered spleen.",
    ["spleen"], "high", True, "negative")

DATA["sporadic"] = w(
    [("speirein", "Greek", "to sow, scatter")],
    "scattered, as sown seed",
    "Greek sporadikos, from speirein, to sow or scatter seed, described things scattered here and there. Sporadic kept that image, describing events that occur scattered irregularly rather than in a steady pattern.",
    ["spore", "diaspora"], "high", True, "neutral")

DATA["sportive"] = w(
    [("des-", "Latin", "away"), ("portare", "Latin", "to carry")],
    "carrying oneself away, diverting",
    "Sport comes from Old French desporter, to divert oneself, from des-, away, and porter, to carry: literally to carry one's mind away from serious matters. Sportive kept that playful, diverting spirit.",
    ["port", "portable", "transport", "export"], "high", True, "positive")

DATA["spurious"] = w(
    [("spurius", "Latin", "of illegitimate birth, false")],
    "of illegitimate birth",
    "Latin spurius originally described a child of illegitimate or unknown parentage. The word extended to anything not of genuine origin, false or counterfeit despite an appearance of authenticity.",
    [], "high", True, "negative")

DATA["spurn"] = w(
    [("spurnan", "Old English", "to kick away, strike with the foot")],
    "to kick away with the foot",
    "Spurn comes from Old English spurnan, to kick away or strike with the foot. To spurn something is to reject it as if kicking it away in contempt.",
    ["spur"], "high", True, "negative")

DATA["squalid"] = w(
    [("squalere", "Latin", "to be rough, filthy, neglected")],
    "rough and crusted with dirt",
    "Latin squalere meant to be stiff and rough with filth or neglect, like skin crusted with dirt. Squalid kept that sense of filthy, degraded conditions.",
    ["squalor"], "high", True, "negative")

DATA["squalor"] = w(
    [("squalere", "Latin", "to be rough, filthy, neglected")],
    "roughness, filthiness",
    "From the same Latin squalere as squalid, squalor names the state itself: filthy, neglected, degraded conditions.",
    ["squalid"], "high", True, "negative")

DATA["squander"] = w(
    [("squander", "English", "uncertain origin, perhaps related to scatter or wander")],
    "unknown, possibly to scatter about",
    "Squander's origin is uncertain, perhaps connected to an old dialect word meaning to scatter or disperse. It settled into meaning to waste money or resources recklessly, scattering them away.",
    [], "low", True, "negative")

DATA["squeamish"] = w(
    [("escoymeux", "Anglo-French", "fastidious, easily disgusted; origin uncertain")],
    "unknown origin, fastidious, easily disgusted",
    "Squeamish traces to an Anglo-French word meaning fastidious or easily disgusted, but its deeper origin is unclear. It has long described a person quick to feel nausea, disgust, or shock at unpleasant things.",
    [], "low", True, "negative")

path = sys.argv[1] if len(sys.argv) > 1 else "08_d.json"
with open(path, "w") as f:
    json.dump(DATA, f, indent=1, ensure_ascii=False)
    f.write("\n")
print(f"wrote {len(DATA)} entries to {path}")
