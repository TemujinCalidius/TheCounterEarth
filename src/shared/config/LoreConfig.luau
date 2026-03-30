-- LoreConfig.luau
-- Defines all lore entries for the Codex system.
-- Full text sourced from lore/game/areas/*/lore/*.md

export type LoreDef = {
	id: string,
	title: string,
	subtitle: string,
	category: string,
	area: string,
	icon: string,
	text: string,
	sortOrder: number,
}

local LoreConfig = {}

-- ── Area ordering (for Codex sidebar) ──────────────────────────────────
LoreConfig.AreaOrder = {
	"The Ward",
	"Melbourne City",
	"Launch Site",
	"Starhaven",
	"Welcome Island",
	"Tempermill",
	"Everdale",
	"Myrkvior Fjord",
}

-- ── All lore entries ───────────────────────────────────────────────────
LoreConfig.Entries = {

	-- === THE WARD (8 entries) ===

	{
		id = "ward_chen_log_1",
		title = "Dr. Chen's Log — Day 1",
		subtitle = "The Flood",
		category = "Medical Log",
		area = "The Ward",
		icon = "\u{1F4CB}",
		sortOrder = 1,
		text = [[12 March — 0340 hrs

Sixteen bite wound cases admitted since midnight. All from the eastern suburbs — Hawthorn, Kew, Camberwell. Ambulances are still coming.

The wounds are unusual. Deep lacerations, ragged edges, tissue avulsion in several cases. More consistent with animal attack than human assault, but the bite patterns are unmistakably human. Full dental arcs. I've seen dog bites and I've seen bar fights. These are neither.

All patients isolated in Ward C per infectious disease protocol. Full PPE for all attending staff. I've requested additional barrier supplies from central stores.

Three of the sixteen are already febrile. Temperatures climbing fast — 38.9, 39.4, 39.7 at last check. Standard antipyretics having minimal effect. I've ordered cooling blankets and blood panels.

Something about the fever patients. They won't stay still. Pulling at restraints, turning their heads, tracking movement across the room. Their pupils are wrong — dilated far beyond what the light levels should produce. Nurse Okafor said one of them watched her the entire time she was changing an IV bag. Didn't blink once.

I've called the Department of Health hotline. No answer. Tried three times. Switchboard says all lines are engaged. Engaged at 3 AM.

I'm going back to Ward C to check the fever patients again. I can hear something from down the corridor. One of them is making a sound — not words, not quite a scream. Something between the two.

It's probably just the fever.

— L.C.]],
	},
	{
		id = "ward_chen_log_2",
		title = "Dr. Chen's Log — Day 3",
		subtitle = "The Turning",
		category = "Medical Log",
		area = "The Ward",
		icon = "\u{1F4CB}",
		sortOrder = 2,
		text = [[14 March

The fever patients in Ward C turned violent overnight. Not agitated — violent. Predatory.

Two orderlies attacked during the 0200 check. Marcus Yeboah is in surgery — bite wounds to the neck and forearm, significant blood loss. The other — James, the new graduate — didn't make it. They found him in the supply closet. I won't write what they found.

Patient in bed six broke through leather four-point restraints. Both wrist straps snapped clean. That should not be physically possible. The tensile strength on those straps is rated for — it doesn't matter. It happened.

I watched one of them turn. Patient Ava Moretti, 34, admitted with bites to both hands. Fever peaked at 41.8 and then she went quiet. Completely still. Eyes open. I thought she was seizing. Then she looked at me and it wasn't her anymore. Same face. Same body. But something else behind the eyes. Like the person had been scooped out and something empty had filled the space.

When they see you, they scream. Not pain. Not fear. Something else. A sound that calls the others.

Then they come running.

Police outside the building. Won't come in.

Quarantine ward patients still stable. Coma patients unchanged. Thank god.

I need to move. Can hear them on this floor now.

More later if there is a later.

— L.C.]],
	},
	{
		id = "ward_chen_log_3",
		title = "Dr. Chen's Log — Day 5",
		subtitle = "The Decision",
		category = "Medical Log",
		area = "The Ward",
		icon = "\u{1F4CB}",
		sortOrder = 3,
		text = [[16 March — 1420 hrs

Hospital evacuation ordered by administration at 0600 this morning. Effective immediately. All ambulatory patients to be discharged or transferred to evacuation points. Non-critical staff to report to assembly areas in the east car park.

Most staff have already left. Some didn't leave — they turned. I watched Dr. Hargreaves from Radiology walk into the stairwell with a bite on his shoulder and come back twenty minutes later as something else. I don't know how many are still human in this building. Not many.

I am making the decision to seal the quarantine ward.

I have seven patients. All on life support. All in medically induced comas. They cannot be moved. Disconnecting them means death — not in hours, in minutes. The evacuation order says critical patients in sealed wards "will be retrieved when conditions stabilize." I don't think conditions are going to stabilize.

The backup generators are on a separate circuit, fuel at 78%. If nothing draws extra load, they should run for weeks. The IV drips are full. I've increased sedation to keep them under as long as possible.

I'm barricading the main ward doors now. Two gurneys wedged against the frame. The supply cart from storage. A maintenance chain through the handles. The doors are fire-rated steel with reinforced glass. Nothing I've seen them do should get through.

My patients:

Bed 1 — Margaret Tsui, 67. Stroke recovery.
Bed 2 — David Anand, 45. Post-surgical coma, spinal fusion.
Bed 3 — Ryan Gallagher, 29. Severe sepsis, organ support.
Bed 4 — Patient ID #4471 — name redacted per records protocol.
Bed 5 — Elaine Chong, 52. Aneurysm repair, induced coma.
Bed 6 — Thomas Wirrarika, 38. Cranial surgery, swelling management.
Bed 7 — Priya Naidu, 19. Drug interaction, cardiac event.

Seven people who trusted this hospital with their lives.

God forgive me. I'm sealing them in to keep them alive. The alternative is worse.

If we can get back, we will. If the power holds, they'll survive. The machines will breathe for them and the drips will keep them under and they'll sleep through whatever is happening outside these walls.

If no one comes back, they'll never know what happened. They'll just stop. One by one, as the drips run dry and the generators go quiet. They'll slip from sleep into nothing, and they won't feel it.

I have to believe that's not how this ends.

— Dr. Lin Chen]],
	},
	{
		id = "ward_chen_log_4",
		title = "Dr. Chen's Log — Day 8",
		subtitle = "The Breach",
		category = "Medical Log",
		area = "The Ward",
		icon = "\u{1F4CB}",
		sortOrder = 4,
		text = [[19 March — time unknown

Building shook 0300 approx. Explosion — gas main? Something outside. East stairwell wall cracked. Partial collapse. There's a gap.

I can hear them in the building now. Lower floors. Moving.

Ward doors holding. Barricade intact. Chain secure.

Checked generators — running. Fuel gauge at 61%. Not critical yet.

Checked all seven patients:

Bed 1: BP 118/76, HR 62. Stable.
Bed 2: BP 125/80, HR 58. Stable.
Bed 3: BP 104/68, HR 71. Declining. Resp support maxed.
Bed 4: BP 122/78, HR 55. Strong. Stable.
Bed 5: BP 115/74, HR 64. Stable.
Bed 6: BP 108/70, HR 68. Stable.
Bed 7: BP 110/72, HR 66. Stable.

All alive. Drips holding.

I can't stay. If they find me they find the ward. I'm a liability now.

The barricade will hold. The doors are steel. They can't think. They'll wander past.

Leaving via maintenance corridor. Going to try for the roof.

If anyone reads this: don't open the ward doors. The patients inside are alive.

— L.C.]],
	},
	{
		id = "ward_chen_log_5",
		title = "Dr. Chen's Log — Final Entry",
		subtitle = "The Farewell",
		category = "Medical Log",
		area = "The Ward",
		icon = "\u{1F4CB}",
		sortOrder = 5,
		text = [[I came back.

I told myself I wouldn't. I told myself the best thing I could do was stay away, keep the noise away, keep them wandering the other floors. But I came back one last time because I needed to see them breathing.

All seven still alive. Machines running. The generators are holding — fuel at 54%, enough for weeks if nothing changes. I've adjusted the IV drips, increased the sedation concentrations. Enough to keep them under for a long time. Maybe long enough.

I checked you last. Bed 4. Your vitals are the strongest of the group — BP 120/76, heart rate steady at 54. Textbook. You came in with a TBI from a motor vehicle collision. Young, healthy before the accident. Your brain has been healing while the world outside fell apart.

If anyone wakes up from this, it'll be you.

I became a doctor because I believed that was enough — that knowing how to help meant you could. I took an oath to do no harm. I have sealed seven people in a room and walked away. I don't know what that makes me.

If you're reading this, you woke up. I'm sorry I wasn't here.

The ward doors are sealed. Steel and chain. Don't try them — the noise will attract what's outside. Find another way out. The maintenance corridor has a service hatch. Check the ceiling panels.

Don't go to the other hospitals. They fell before we did. Don't trust anyone who's feverish, anyone shaking, anyone whose eyes look wrong. The fever means it's already too late for them. You can't help them. I know that's hard. Believe me.

There's been talk — before the radios went dead — of a way out. Something in the sky, past the city. I don't know if it's real. I don't know if anything is real anymore past these walls.

But you're alive, and that's something I did right.

Survive. That's all I have left to give you.

— Dr. Lin Chen]],
	},
	{
		id = "ward_evacuation",
		title = "Hospital Evacuation Notice",
		subtitle = "Official Order",
		category = "Notice",
		area = "The Ward",
		icon = "\u{1F4C4}",
		sortOrder = 6,
		text = [[ROYAL MELBOURNE HOSPITAL
EMERGENCY EVACUATION ORDER

Effective: Immediately — 16 March, 0600 hrs
Authority: Hospital Administration, in coordination with DHHS Victoria
Classification: Critical — All Personnel

All ambulatory patients are to be discharged or transferred to designated evacuation assembly points (East Car Park, Levels G-2). Non-critical staff are to report to their assigned assembly coordinator no later than 0800 hrs.

Surgical cases in progress will be completed at the attending surgeon's discretion. No new admissions are to be accepted.

Critical patients in sealed or quarantine wards will remain in situ and will be retrieved when conditions stabilize. Life support systems are to be maintained on backup generator circuits. Attending physicians are to document patient status before departing.

All departing staff must sign out at the east checkpoint. Personal vehicles are not to be used. Transport will be provided.

This order supersedes all standard shift scheduling.

Signed,
Dr. Robert Hannigan
Chief Medical Officer, Royal Melbourne Hospital

Handwritten at the bottom, in different ink:

Conditions did not stabilize. — L.C.]],
	},
	{
		id = "ward_quarantine",
		title = "Quarantine Protocol",
		subtitle = "Infection Control",
		category = "Notice",
		area = "The Ward",
		icon = "\u{1F4C4}",
		sortOrder = 7,
		text = [[ROYAL MELBOURNE HOSPITAL — INFECTION CONTROL
Quick Reference: Quarantine Isolation Procedure

1. Identify suspected infectious patient. Notify charge nurse immediately.
2. Isolate patient in negative-pressure room. Engage airlock seal.
3. All attending staff to don full PPE: N95 respirator, face shield, gown, double gloves.
4. Initiate contact tracing. Log all personnel with patient exposure in the last 48 hrs.
5. Notify Infection Control Officer (ext. 4457).
6. Notify Department of Health via hotline (1800 675 398).
7. Maintain isolation until clearance from Infection Control.
8. Decontaminate all surfaces and equipment per Protocol 7C.

Reporting Chain: Charge Nurse > Infection Control > Department of Health

Every step above has been crossed out in black marker.

Handwritten at the bottom:

None of this works. They don't cough. They bite.]],
	},
	{
		id = "ward_patient_chart",
		title = "Patient Chart — Bed 4",
		subtitle = "Your Record",
		category = "Personal",
		area = "The Ward",
		icon = "\u{1F3E5}",
		sortOrder = 8,
		text = [[ROYAL MELBOURNE HOSPITAL — PATIENT RECORD

Patient ID: #4471
Name: ————
DOB: ————
Bed: 4, Quarantine Ward (Sealed)

Admission Date: 22 February
Admitting Physician: Dr. L. Chen
Reason for Admission: Traumatic brain injury — motor vehicle collision. GCS 6 on arrival. Intracranial haemorrhage with cerebral oedema. Emergency craniotomy performed 22/02. Post-surgical induced coma for swelling management.

Status: Induced coma — monitor and reassess weekly.

Medication: Propofol infusion 4mg/kg/hr. Midazolam 0.05mg/kg/hr adjunct. Adjust per ICP readings.

Observations:

23 Feb — BP 128/82, HR 64, Temp 36.8, ICP 18
  Post-op stable. Swelling as expected.

25 Feb — BP 124/78, HR 60, Temp 36.7, ICP 16
  ICP trending down. Good sign.

01 Mar — BP 122/76, HR 58, Temp 36.6, ICP 14
  Steady improvement. Neuro response positive.

08 Mar — BP 120/76, HR 56, Temp 36.5, ICP 12
  Excellent recovery trajectory. Plan to begin weaning sedation next week.

12 Mar — BP 120/76, HR 55, Temp 36.5, ICP 11
  Weaning postponed. See incident report.

16 Mar — BP 122/78, HR 55, Temp 36.5, ICP 11
  Vitals stable. Generator power. Sealing ward. Patient to remain in coma. Will return when possible. — L.C.

No further entries.]],
	},
}

-- ── Build lookup tables ────────────────────────────────────────────────

LoreConfig.ById = {} :: { [string]: LoreDef }
for _, entry in ipairs(LoreConfig.Entries) do
	LoreConfig.ById[entry.id] = entry
end

LoreConfig.ByArea = {} :: { [string]: { LoreDef } }
for _, entry in ipairs(LoreConfig.Entries) do
	if not LoreConfig.ByArea[entry.area] then
		LoreConfig.ByArea[entry.area] = {}
	end
	table.insert(LoreConfig.ByArea[entry.area], entry)
end

LoreConfig.TotalCount = #LoreConfig.Entries

return LoreConfig
