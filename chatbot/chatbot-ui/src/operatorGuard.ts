/* eslint-disable */
import fs from 'fs';

type Fingerprint = {
  schema: 'devmode.v3';
  mode: 'developer';
  one_step: true;
  risk_meter: 'on';
  paste_ready_code: true;
};

export function requireOperatorFingerprint() {
  const p = 'C:/AiProject/mode/dev.fingerprint.json';
  let raw: string;
  try { raw = fs.readFileSync(p, 'utf8'); } catch {
    throw new Error(\[OperatorGuard] fingerprint missing at \\);
  }
  const j = JSON.parse(raw) as Fingerprint;
  const fail = (m:string)=>{ throw new Error(\[OperatorGuard] \\); };
  if (j.schema !== 'devmode.v3') fail('schema mismatch');
  if (j.mode !== 'developer') fail('mode must be developer');
  if (j.one_step !== true) fail('one_step must be true');
  if (j.risk_meter !== 'on') fail('risk_meter must be on');
  if (j.paste_ready_code !== true) fail('paste_ready_code must be true');
}

