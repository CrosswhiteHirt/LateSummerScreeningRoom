#!/usr/bin/env python3
"""Editorial pass over the generated English story localization.

Machine translation provides the first draft; this pass applies the spelling,
names, and cinematic terminology established in the local screenplay documents.
"""

from __future__ import annotations

import json
import re
from pathlib import Path


STORY = Path(__file__).resolve().parents[1] / "GameTemplate" / "GameTemplate" / "Resources" / "StoryContent.json"

EXACT = {
    "2. Prologue: Lies on Film": "Prologue: Lies on Film",
    "3. Chapter 1: The non-existent fifth person": "Chapter 1: The Fifth Person Who Wasn't There",
    "4. Chapter 2: Lines written tomorrow": "Chapter 2: Lines Written for Tomorrow",
    "5. Chapter 3: Person whose name is deleted": "Chapter 3: The One Who Erased a Name",
    "6. Chapter 4: Typhoon Night": "Chapter 4: Typhoon Night",
    "7. Chapter 5: The last screening": "Chapter 5: The Final Screening",
    "8. Hidden ending: written to September": "Hidden Ending: A Letter to September",
    "Scene 1: Return to Shiomizaka": "Scene 1: Back to Shiomizaka",
    "Scene 2: Old house and mailbox": "Scene 2: The Old House and Its Mailbox",
    "Scene 3: Myself in the film": "Scene 3: Myself on Film",
    "Scene 1: The final movie department": "Scene 1: The Last Film Club",
    "Scene 2: \"The First Day of September\"": "Scene 2: The First Day of September",
    "Scene 3: First screening": "Scene 3: The First Screening",
    "Scene One: Script Prophecy": "Scene 1: The Script's Prophecy",
    "Scene 2: Girl at dusk": "Scene 2: A Girl at Dusk",
    "Scene 3: Yuzhen’s tape": "Scene 3: Yuma's Tape",
    "Scene 1: Cropped photo": "Scene 1: The Cut-Up Photograph",
    "Scene 2: Lies in the lamp": "Scene 2: Akari's Lie",
    "Scenario 3: Don’t let them remember": "Scene 3: Don't Let Them Remember",
    "Scene 4: Blue in the prop box": "Scene 4: Blue in the Prop Box",
    "Scene 1: Seagull Cinema": "Scene 1: Seagull Cinema",
    "Scene 2: The accident five years ago": "Scene 2: The Accident Five Years Ago",
    "Scene 3: Forget the tide bell": "Scene 3: The Forget-the-Tide Bell",
    "Ending 1: Only summer remains": "Ending 1: Only Summer Remains",
    "Ending 2: There is no fifth person": "Ending 2: No Fifth Person",
    "Ending 3: The other side of the sea": "Ending 3: The Other Side of the Sea",
    "Ending 4: After the screening": "Ending 4: After the Screening",
    "Unlock conditions": "Unlock Conditions",
    "Recordings damaged by seawater": "Water-Damaged Recording",
    "The erased screenwriter's signature": "Erased Screenwriter Credit",
    "The last undeveloped photo": "Last Undeveloped Photograph",
    "blue glass hairpin": "Blue-Glass Hairclip",
    "scratched-out name": "Scratched-Out Name",
    "fifth cup": "The Fifth Cup",
    "To Sahara Riku.": "To Riku Sahara.",
    "Shiomizaka Academy is a middle school and high school integrated school.": "Shiomizaka Academy combines middle and high school.",
    "Five years ago, twelve-year-old Riku, Akari, Shiori and Chinatsu, and thirteen-year-old Yuma participated in a summer movie event jointly organized by the academy and the town cultural center.": "Five years ago, twelve-year-old Riku, Akari, Shiori, and Chinatsu, along with thirteen-year-old Yuma, took part in a summer film event organized by the school and the town cultural center.",
    "The screenwriter column only has \"Fuyutsuki Shiori\".": "The screenwriter credit lists only \"Shiori Fuyutsuki.\"",
    "Riku Meng then retreated.": "Riku abruptly recoiled.",
    "Shiori then found a copy of the registration form for the summer movie event, a photo bag kept by the club, and a copy of that year's competition application.": "Shiori then found the summer-film event registration form, the club's photo envelope, and a copy of that year's competition entry.",
    "You are now very good at tidying up.": "You've gotten really good at tidying up.",
    "The sea breeze blows the \"Forgotten Tide Bell\" in the shrine.": "Sea wind stirs the Forget-the-Tide Bell at the shrine.",
    "Riku Xian destroyed the photos, script signatures and activity materials that the five people had in hand, trying to get everyone to stop touching the wounds.": "Riku first destroyed the photographs, script credits, and activity materials the five of them held, hoping everyone would stop reopening the wound.",
    "Later, he made a wish to Forget-the-Tide Bell and stored the memory of Chinatsu in the master tape that he had never thrown away.": "Later, he made a wish at the Forget-the-Tide Bell and sealed Chinatsu's memories inside the master tape he had never discarded.",
    "Riku Yuan thought that the camera did not capture Chinatsu.": "Riku had assumed the camera hadn't captured Chinatsu.",
    "\"Late Summer Screening Room\"": "\"The End-of-Summer Screening Room\"",
    "Survey Choice: Whether to Save Hairpins": "Survey Choice: Save the Hairclip",
    "When his father was young, he maintained projection equipment for the school, and Riku also learned the most basic operations during summer movie activities when he was a child.": "Riku learned basic projection work from his father during the school's summer film events.",
    "Five years ago, twelve-year-old Riku, Akari, Shiori, and Chinatsu, along with thirteen-year-old Yuma, took part in a summer film event organized by the school and the town cultural center.": "Five years ago, twelve-year-old Riku, Akari, Shiori, and Chinatsu, along with thirteen-year-old Yuma, joined a summer film event run by the school and town cultural center.",
    "Now, the Film Studies Department has received permission from its instructors and school officials to continue using the safety-inspected activity room and auditorium before closing.": "The Film Club may use the safety-cleared clubroom and auditorium until the school closes.",
    "Five years ago, a film event was allowed to be filmed there; after the event, the five children returned privately without telling the teacher in order to make up for the last scene.": "After a film event five years ago, the five children secretly returned here to reshoot the final scene.",
    "The school contacted the town cultural center to obtain an entry permit, and management personnel completed structural, circuit and water inspections, and restricted everyone to enter the open area only during the day.": "The school arranged a permit and safety inspections; they may enter only the open areas by day.",
    "The weight of the scroll is a bit more than the label, and the innermost layer is stuck into a hard circle by seawater and emulsion, making it temporarily unable to be unfolded.": "The reel is heavier than its label suggests; seawater and emulsion have fused its inner layer into a hard coil.",
    "Yuma uploaded the film, restoration records, and public search and rescue notices from five years ago to the digital archive page of the town cultural center with the consent of the parties concerned.": "With everyone's consent, Yuma uploaded the film, restoration notes, and old public search notices to the town cultural center's digital archive.",
    "Accompany Youzhen to complete the security check at the door, and then go in together": "Go through security with Yuma and enter together.",
    "When his father was young, he maintained projection equipment for the school, and Riku also learned the most basic operations during summer movie activities when he was a child.": "Riku learned basic projection work from his father during the school's summer film events.",
    "Five years ago, twelve-year-old Riku, Akari, Shiori and Chinatsu, and thirteen-year-old Yuma participated in a summer movie event jointly organized by the academy and the town cultural center.": "Five years ago, twelve-year-old Riku, Akari, Shiori, and Chinatsu, along with thirteen-year-old Yuma, joined a summer film event run by the school and town cultural center.",
    "Five years ago, twelve-year-old Riku, Akari, Shiori, and Chinatsu, along with thirteen-year-old Yuma, joined a summer film event run by the school and town cultural center.": "Five years ago, twelve-year-old Riku, Akari, Shiori, and Chinatsu joined a summer film event with thirteen-year-old Yuma.",
    "Yuma uploaded the film, restoration records, and public search and rescue notices from five years ago to the digital archive page of the town cultural center with the consent of the parties concerned.": "With everyone's consent, Yuma uploaded the film, restoration notes, and old public search notices to the town cultural center's digital archive.",
}

WORD_REPLACEMENTS = {
    "Dengli": "Akari", "Denri": "Akari", "Touri": "Akari",
    "Qianxia": "Chinatsu", "Yuzhen": "Yuma", "Yuuma": "Yuma",
    "Sahara Riku": "Riku Sahara", "Riku Sawara": "Riku Sahara",
    "Tsukijo Chinatsu": "Chinatsu Tsukishiro",
    "Chinatsu Tsukijo": "Chinatsu Tsukishiro",
    "Tsukijo": "Tsukishiro",
    "Wangchao Ling": "Forget-the-Tide Bell",
    "Shiomizaka Folklore Copy": "Shiomizaka Folklore Archive",
    "Film Research Department": "Film Club",
    "blue glass hairpin": "blue-glass hairclip",
    "blue hairpin": "blue-glass hairclip",
    "hairpins": "hairclip",
    "hairpin": "hairclip",
    "In the young lamp": "Young Akari",
    "Young man land": "Young Riku",
    "Young man Riku": "Young Riku",
    "young man Riku": "Young Riku",
    "young Lu": "Young Riku",
    "Young Lu": "Young Riku",
    "new life": "new student",
}


def polish(value: str) -> str:
    value = EXACT.get(value, value)
    for source, target in WORD_REPLACEMENTS.items():
        value = value.replace(source, target)
    value = re.sub(r"\bLu\b", "Riku", value)
    value = re.sub(r"\bland\b", "Riku", value, flags=re.IGNORECASE)
    return value


def visit(value):
    if isinstance(value, dict):
        return {key: visit(item) for key, item in value.items()}
    if isinstance(value, list):
        return [visit(item) for item in value]
    return polish(value) if isinstance(value, str) else value


def main() -> None:
    story = json.loads(STORY.read_text())
    story = visit(story)
    speaker_names = {
        "Chinatsu whispered to the camera": "Chinatsu",
        "On the back of the photo it says": "",
        "Strange girl's voice": "Unknown Girl",
        "Yuma in reality": "Yuma",
        "girl": "Girl",
        "new student": "New Student",
        "someone shouts": "Voice",
    }
    for node in story["nodes"].values():
        if node.get("speaker") in speaker_names:
            node["speaker"] = speaker_names[node["speaker"]]
    STORY.write_text(json.dumps(story, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
