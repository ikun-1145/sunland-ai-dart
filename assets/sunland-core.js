var jn = Object.defineProperty;
var yn = (e, t, n) => t in e ? jn(e, t, { enumerable: !0, configurable: !0, writable: !0, value: n }) : e[t] = n;
var L = (e, t, n) => yn(e, typeof t != "symbol" ? t + "" : t, n);
const p = {
  /** Inheritance / subclass-of, e.g. 猫 属于 哺乳动物 */
  IsA: "属于",
  /** Identity / instance-of, e.g. 苏格拉底 是 人 */
  Is: "是",
  /** Capability, e.g. 鸟 会 飞 */
  Can: "会",
  /** Preference, e.g. 猫 喜欢 鱼 */
  Likes: "喜欢",
  /** Spatial location, e.g. 猫 在 屋顶 */
  LocatedIn: "在"
}, ne = {
  Name: "name"
};
let mt = 0;
function On() {
  return mt += 1, `k_${Date.now().toString(36)}_${mt.toString(36)}`;
}
const Sn = 1, En = "user";
function de(e) {
  return `${e.subject} ${e.relation} ${e.object} ${e.negated}`;
}
function Ae(e, t, n) {
  const r = e.get(t);
  r === void 0 ? e.set(t, /* @__PURE__ */ new Set([n])) : r.add(n);
}
function ve(e, t, n) {
  const r = e.get(t);
  r !== void 0 && (r.delete(n), r.size === 0 && e.delete(t));
}
function wn(e) {
  const t = [...e].sort((c, s) => c.size - s.size), [n, ...r] = t;
  if (n === void 0) return /* @__PURE__ */ new Set();
  let i = n;
  for (const c of r) {
    const s = /* @__PURE__ */ new Set();
    for (const a of i)
      c.has(a) && s.add(a);
    if (i = s, i.size === 0) break;
  }
  return i;
}
function Cn(e, t) {
  return !(t.subject !== void 0 && e.subject !== t.subject || t.relation !== void 0 && e.relation !== t.relation || t.object !== void 0 && e.object !== t.object || t.negated !== void 0 && e.negated !== t.negated);
}
function Rn(e) {
  if (Number.isNaN(e) || e < 0 || e > 1)
    throw new RangeError(`confidence must be within [0, 1], got ${e}`);
}
class vt {
  constructor() {
    L(this, "records", /* @__PURE__ */ new Map());
    L(this, "bySubject", /* @__PURE__ */ new Map());
    L(this, "byRelation", /* @__PURE__ */ new Map());
    L(this, "byObject", /* @__PURE__ */ new Map());
    L(this, "idByTripleKey", /* @__PURE__ */ new Map());
  }
  all() {
    return Array.from(this.records.values());
  }
  has(t) {
    return this.idByTripleKey.has(de(t));
  }
  match(t) {
    const n = [];
    t.subject !== void 0 && n.push(this.bySubject.get(t.subject) ?? /* @__PURE__ */ new Set()), t.relation !== void 0 && n.push(this.byRelation.get(t.relation) ?? /* @__PURE__ */ new Set()), t.object !== void 0 && n.push(this.byObject.get(t.object) ?? /* @__PURE__ */ new Set());
    const r = n.length > 0 ? wn(n) : this.records.keys(), i = [];
    for (const c of r) {
      const s = this.records.get(c);
      s !== void 0 && Cn(s, t) && i.push(s);
    }
    return i;
  }
  add(t, n) {
    const r = this.idByTripleKey.get(de(t));
    if (r !== void 0) {
      const s = this.records.get(r);
      if (s !== void 0) return s;
    }
    const i = (n == null ? void 0 : n.confidence) ?? Sn;
    Rn(i);
    const c = {
      subject: t.subject,
      relation: t.relation,
      object: t.object,
      negated: t.negated,
      id: On(),
      confidence: i,
      source: (n == null ? void 0 : n.source) ?? En,
      createdAt: (/* @__PURE__ */ new Date()).toISOString()
    };
    return this.insertRecord(c), c;
  }
  addMany(t) {
    for (const n of t)
      this.records.has(n.id) || this.insertRecord(n);
  }
  remove(t) {
    const n = this.records.get(t);
    n !== void 0 && (this.records.delete(t), this.idByTripleKey.delete(de(n)), ve(this.bySubject, n.subject, t), ve(this.byRelation, n.relation, t), ve(this.byObject, n.object, t));
  }
  clear() {
    this.records.clear(), this.bySubject.clear(), this.byRelation.clear(), this.byObject.clear(), this.idByTripleKey.clear();
  }
  insertRecord(t) {
    this.records.set(t.id, t), this.idByTripleKey.set(de(t), t.id), Ae(this.bySubject, t.subject, t.id), Ae(this.byRelation, t.relation, t.id), Ae(this.byObject, t.object, t.id);
  }
}
const kn = [
  { subject: "猫", relation: p.IsA, object: "哺乳动物", negated: !1 },
  { subject: "哺乳动物", relation: p.IsA, object: "动物", negated: !1 },
  { subject: "苏格拉底", relation: p.Is, object: "人", negated: !1 },
  { subject: "人", relation: p.IsA, object: "动物", negated: !1 },
  { subject: "鸟", relation: p.Can, object: "飞", negated: !1 },
  { subject: "企鹅", relation: p.IsA, object: "鸟", negated: !1 },
  { subject: "企鹅", relation: p.Can, object: "飞", negated: !0 },
  { subject: "猫", relation: p.Likes, object: "鱼", negated: !1 },
  { subject: "猫", relation: p.LocatedIn, object: "屋顶", negated: !1 }
];
function zn(e) {
  for (const t of kn)
    e.add(t, { source: "seed" });
}
function In(e, t, n) {
  t.setItem(n, JSON.stringify(e.all()));
}
function Nn(e, t, n) {
  const r = t.getItem(n);
  if (r === null) return;
  let i;
  try {
    i = JSON.parse(r);
  } catch {
    return;
  }
  Array.isArray(i) && e.addMany(i);
}
const G = "Sunland AI · Beta", Tn = "霜蓝", xt = "开发者", An = [
  {
    subject: G,
    relation: p.Is,
    object: "一个可以学习你提供的信息，并根据已有知识回答和推理的小助手",
    negated: !1
  },
  {
    subject: Tn,
    relation: p.Is,
    object: "Sunland AI · Beta 当前使用的默认回复人格，语气温和、简洁，偶尔带一点活力；只影响表达方式，不改变事实或推理结论",
    negated: !1
  },
  {
    subject: G,
    relation: p.Can,
    object: "记住你教给我的信息（比如「猫属于哺乳动物」），并在之后的对话里参考",
    negated: !1
  },
  {
    subject: G,
    relation: p.Can,
    object: "根据已知事实回答和推理，当你问“为什么”时，也能说明得出答案的依据",
    negated: !1
  },
  {
    subject: G,
    relation: xt,
    object: "由一名独立开发者持续设计与打磨，目前仍在成长中",
    negated: !1
  }
];
function vn() {
  const e = new vt();
  for (const t of An)
    e.add(t, { source: "seed" });
  return e;
}
function xn() {
  return new vt();
}
let bt = 0;
function $n() {
  return bt += 1, `mem_${Date.now().toString(36)}_${bt.toString(36)}`;
}
class Ln {
  constructor() {
    L(this, "records", /* @__PURE__ */ new Map());
  }
  remember(t, n) {
    const r = (/* @__PURE__ */ new Date()).toISOString(), i = this.records.get(t), c = i ? { ...i, value: n, updatedAt: r } : { id: $n(), key: t, value: n, createdAt: r, updatedAt: r };
    return this.records.set(t, c), c;
  }
  recall(t) {
    return this.records.get(t) ?? null;
  }
  forget(t) {
    this.records.delete(t);
  }
  list() {
    return Array.from(this.records.values());
  }
  search(t) {
    const n = t.toLowerCase();
    return this.list().filter(
      (r) => r.key.toLowerCase().includes(n) || r.value.toLowerCase().includes(n)
    );
  }
  restore(t) {
    for (const n of t)
      this.records.has(n.key) || this.records.set(n.key, n);
  }
}
function _n(e, t, n) {
  t.setItem(n, JSON.stringify(e.list()));
}
function Kn(e, t, n) {
  const r = t.getItem(n);
  if (r === null) return;
  let i;
  try {
    i = JSON.parse(r);
  } catch {
    return;
  }
  Array.isArray(i) && e.restore(i);
}
function Mn() {
  return new Ln();
}
const Pn = /\s+/gu, Dn = /[呀啊呢哦啦~～]+$/u;
function gt(e) {
  return e.replace(Pn, "").replace(Dn, "").toLowerCase();
}
function Se(e, t, n = 0.95) {
  const r = new Set(t.map(gt));
  return {
    intent: e,
    match(i) {
      return r.has(gt(i)) ? { entities: [], confidence: n } : null;
    }
  };
}
const Un = [
  "你好",
  "您好",
  "哈喽",
  "哈啰",
  "嗨",
  "hi",
  "hello",
  "hey"
];
function qn() {
  return Se("Greeting", Un);
}
const Bn = [
  "谢谢",
  "谢了",
  "感谢",
  "多谢",
  "thanks",
  "thank you",
  "thx"
];
function Fn() {
  return Se("Thanks", Bn);
}
const Wn = [
  "再见",
  "拜拜",
  "88",
  "bye",
  "goodbye",
  "see you"
];
function Vn() {
  return Se("Farewell", Wn);
}
const ht = "Sunland AI · Beta", Gn = "霜蓝";
function Yn(e) {
  return e.includes("霜蓝") || e.includes("frost") ? Gn : e.includes("sunland") || e.includes("你") ? ht : null;
}
const Qn = ["谁开发", "谁做的", "谁创造", "谁写的", "开发者"], Hn = ["能做什么", "会做什么", "能干什么", "能做啥", "会做啥", "能干嘛", "有什么能力", "擅长什么"], Jn = ["是谁", "叫什么", "是什么", "你的名字", "名字是"];
function Xn(e) {
  return Qn.some((t) => e.includes(t)) ? "creator" : Hn.some((t) => e.includes(t)) ? "capability" : Jn.some((t) => e.includes(t)) ? "identity" : null;
}
function Zn() {
  return {
    intent: "Identity",
    match(e) {
      const t = e.toLowerCase(), n = Yn(t), r = Xn(t);
      return n === null || r === null ? null : { entities: [n, r], confidence: 0.9 };
    }
  };
}
const er = [
  "我叫什么",
  "我叫什么名字",
  "你知道我的名字吗",
  "你记得我叫什么吗",
  "你记得我的名字吗",
  "你还记得我的名字吗",
  "还记得我是谁吗"
];
function tr() {
  return Se("RecallName", er);
}
const Ue = Object.freeze({
  maxInputLength: 160,
  maxNameLength: 64,
  maxRelationMentions: 1
}), nr = /[,，;；。.!！?？\r\n]/u, rr = /[。.!！]+$/u, ir = /[?？]|(?:是不是|会不会|有没有|能不能|属不属于|为什么|怎么|什么|啥|谁|哪里|哪儿|吗|呢)(?:[啊呀呢哦啦]?[。.!！]?)$/u, cr = /(?:还是|或者|或是|然后|并且|而且|同时|接着|另外)/u, sr = /(?:不要|别|无需|不用|禁止)(?:再)?(?:记住|记|保存|学习|教)/u, ar = Object.freeze([
  "指的是",
  "意思是",
  "是一种",
  "属于",
  "喜欢",
  "拥有",
  "具备",
  "会",
  "有",
  "是",
  "在"
]);
function $t(e) {
  return e.trim().replace(rr, "").trim();
}
function or(e) {
  return nr.test(
    $t(e)
  );
}
function ur(e) {
  return ir.test(e.trim());
}
function Lt(e) {
  return cr.test(e);
}
function _t(e) {
  return sr.test(e);
}
function Kt(e) {
  let t = e, n = 0;
  for (const r of ar) {
    let i = t.indexOf(r);
    for (; i >= 0; )
      n += 1, t = t.slice(0, i) + " ".repeat(r.length) + t.slice(i + r.length), i = t.indexOf(r);
  }
  return n;
}
function et(e) {
  const t = e.trim();
  return t.length === 0 || t.length > Ue.maxInputLength || or(t) || ur(t) || Lt(t) || _t(t) || Kt(t) > Ue.maxRelationMentions;
}
function qe(e) {
  return $t(e).replace(/\s+/gu, " ").trim();
}
const lr = [
  /^我\s*叫\s*(.+)$/iu,
  /^我的名字\s*是\s*(.+)$/iu,
  /^你可以\s*叫我\s*(.+)$/iu,
  /^叫我\s*(.+)$/iu
], fr = /* @__PURE__ */ new Set(["什么", "什么名字", "谁"]), dr = /^(?:你好|您好|嗨|哈喽|hello|hi)[,，]\s*/iu, mr = /[呀啊呢哦啦吧~～]+$/u, br = /^[\p{P}\p{S}\s]+$/u;
function gr(e) {
  const t = e.trim().replace(dr, "");
  if (et(t))
    return null;
  for (const n of lr) {
    const r = n.exec(t);
    if (!r) continue;
    const i = qe(r[1] ?? "").replace(mr, "").trim();
    return i.length === 0 || i.length > Ue.maxNameLength || fr.has(i) || br.test(i) || Lt(i) || Kt(i) > 0 ? null : i;
  }
  return null;
}
function hr() {
  return {
    intent: "RememberName",
    match(e, t) {
      const n = gr(t ?? e);
      return n === null ? null : { entities: [n], confidence: 0.95 };
    }
  };
}
const pr = [
  qn(),
  Fn(),
  Vn(),
  tr(),
  Zn(),
  hr()
], jr = /\s+/gu, yr = /[?？!！。.,，;；]+$/u;
function Or(e) {
  return e.replace(jr, "").replace(yr, "");
}
function Ee(e) {
  return e.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
function Sr(e) {
  return [...e].map((t) => Ee(t)).join("\\s*");
}
function Be(e, t = [e]) {
  const n = [...t].sort((i, c) => c.length - i.length).map(Sr).join("|"), r = new RegExp(
    `^\\s*(.+?)\\s*(不|没)?\\s*(?:${n})\\s*(.+?)\\s*[。.!！]*\\s*$`,
    "u"
  );
  return {
    name: `statement:${e}`,
    match(i, c) {
      const s = c ?? i;
      if (et(s))
        return null;
      const a = r.exec(s);
      if (!a) return null;
      const [, o, d, l] = a;
      if (!o || !l) return null;
      const b = qe(o), g = qe(l);
      return !b || !g ? null : {
        type: "statement",
        subject: b,
        relation: e,
        object: g,
        negated: d === "不" || d === "没",
        raw: s
      };
    }
  };
}
function Er(e) {
  const t = Ee(e), n = new RegExp(`^(.+?)${t}什么$`, "u");
  return {
    name: `query:object-of:${e}`,
    match(r) {
      const i = n.exec(r);
      if (!i) return null;
      const [, c] = i;
      return c ? {
        type: "query",
        subject: c,
        relation: e,
        kind: "object-of",
        raw: r
      } : null;
    }
  };
}
function wr(e) {
  return `${e.charAt(0)}不${e}`;
}
function Cr(e) {
  const t = wr(e), n = Ee(t), r = new RegExp(`^(.+?)${n}(.+)$`, "u");
  return {
    name: `query:verify:${e}`,
    match(i) {
      const c = r.exec(i);
      if (!c) return null;
      const [, s, a] = c;
      return !s || !a ? null : {
        type: "query",
        subject: s,
        relation: e,
        object: a,
        kind: "verify",
        raw: i
      };
    }
  };
}
const Rr = /^(.+?)在哪里$/u;
function kr() {
  return {
    name: "query:locate",
    match(e) {
      const t = Rr.exec(e);
      if (!t) return null;
      const [, n] = t;
      return n ? {
        type: "query",
        subject: n,
        relation: p.LocatedIn,
        kind: "locate",
        raw: e
      } : null;
    }
  };
}
function zr(e) {
  const t = Ee(e), n = new RegExp(`^(.+?)为什么${t}(.+)$`, "u");
  return {
    name: `query:why:${e}`,
    match(r) {
      const i = n.exec(r);
      if (!i) return null;
      const [, c, s] = i;
      return !c || !s ? null : {
        type: "query",
        subject: c,
        relation: e,
        object: s,
        kind: "verify",
        explain: !0,
        raw: r
      };
    }
  };
}
const me = [
  p.IsA,
  p.Is,
  p.Can,
  p.Likes,
  p.LocatedIn
], Ir = [
  Be("意思是", ["指的是", "意思是"]),
  Be("有")
], Nr = [
  kr(),
  ...me.map(zr),
  ...me.map(Cr),
  ...me.map(Er),
  ...Ir,
  ...me.map(
    (e) => Be(e)
  )
];
class Tr {
  constructor(t = Nr, n = pr) {
    L(this, "patterns");
    L(this, "intentMatchers");
    this.patterns = t, this.intentMatchers = n;
  }
  parse(t) {
    const n = Or(t);
    if (!n)
      return { type: "unknown", raw: t, reason: "输入为空" };
    for (const r of this.intentMatchers) {
      const i = r.match(n, t);
      if (i)
        return {
          type: "intent",
          intent: r.intent,
          entities: i.entities ?? [],
          confidence: i.confidence,
          raw: t
        };
    }
    for (const r of this.patterns) {
      const i = r.match(n, t);
      if (i)
        return { ...i, raw: t };
    }
    return {
      type: "unknown",
      raw: t,
      reason: `没有匹配的语法规则："${n}"`
    };
  }
}
function Mt() {
  return new Tr();
}
function Pt(...e) {
  return e.filter((t) => !!(t && t.length > 0)).join(" ");
}
function Ar(e) {
  let t = 0;
  for (let n = 0; n < e.length; n += 1)
    t = t * 31 + e.charCodeAt(n) | 0;
  return Math.abs(t);
}
function O(e, t) {
  if (e.length === 0)
    throw new Error("pickBySeed: `items` must not be empty");
  const n = Ar(t) % e.length;
  return e[n];
}
const vr = [
  "简单来说，",
  "就目前知道的信息来看，",
  "我会这样回答："
], xr = [
  "关于这个问题，我看了看目前掌握的信息。",
  "关于这个问题，",
  "就现有信息来看，"
], $r = [
  "你可以补充一点背景，或者直接教我一条相关信息，我会继续试着回答。",
  "如果你愿意告诉我一些相关信息，我会把它保存在你的知识库里，之后再接着聊。",
  "也可以换一种方式问问看，或者先告诉我一条相关信息。"
], Lr = [
  "不过我对这个答案还没有十足把握，可以再核对一下。",
  "这部分我不太确定，可以把它当作一个待确认的答案。",
  "这个结论的把握不高，最好再确认一下。"
], _r = [
  "好，这条信息我按你刚才提供的内容记下啦，已放进你的知识库：",
  "收到，我把这条信息按你的说法记进知识库了：",
  "明白，这条信息已经记在你的知识库里："
], Kr = [
  "以后你问到相关内容时，我会参考它。",
  "下次聊到相关内容时，我们可以从这条信息接着说。",
  "之后再问到它，我会把这条信息作为已知内容。"
], Mr = [
  "这句话我还没完全接住呢。",
  "这个问题，我现在还缺少一点上下文。"
], Pr = [
  "你可以补充一点背景，或者换一种说法，我会继续试着理解。",
  "如果愿意，再告诉我一点相关信息，或者换个方式问问看。"
], Dr = [
  "你好，我是霜蓝，Sunland AI 的知识伙伴。你可以和我聊聊，也可以教我一条信息，再问我相关问题。",
  "嗨，我是霜蓝，Sunland AI 的知识伙伴。想教我新信息，或问问我已经知道的内容，都可以从这里开始。",
  "你好，我是霜蓝，Sunland AI 的知识伙伴。可以先告诉我一条信息，再用问题考考我。",
  "嗨，我是霜蓝，Sunland AI 的知识伙伴。普通知识或你的兽设设定，都可以先告诉我，再问我相关问题。"
  // furry nod
], Ur = [
  "不客气，能帮上忙就好啦。",
  "不用谢，有想继续聊的就告诉我。",
  "好呀，之后有问题也可以接着问。",
  "能和你一起理清就好。"
], qr = [
  "再见，下次想继续时再来找我。",
  "那就先聊到这里啦，下次见。",
  "好，我们下次再接着聊。",
  "再见，祝你接下来一切顺利。"
], Br = [
  "现在和你说话的是霜蓝，是 Sunland AI 当前使用的回复人格。",
  "我是霜蓝，负责呈现 Sunland AI 的回复。"
], Fr = [
  "你可以教我一条新信息，或者直接问我已经知道的内容。",
  "想试试的话，可以先告诉我一条信息，再问一个相关问题。"
], Wr = [
  "我可以",
  "目前我可以"
], Vr = [
  "想试试的话，可以先教我一条信息，再问一个相关问题。",
  "你可以直接教我一条信息，或者问一个已经教过的问题。"
], Gr = [
  "Sunland AI",
  "目前，Sunland AI"
], Yr = [
  "现在仍处于持续完善阶段。",
  "目前仍在继续打磨中。"
], Qr = [
  "好，我记下啦，你叫",
  "收到，我会称呼你为",
  "明白，你的名字是"
], Hr = [
  "之后在这个账号里，我会这样称呼你。",
  "接下来聊天时，我会用这个名字。",
  "之后聊到名字时，我会参考这条记忆。"
], Jr = [
  "我记得，你是",
  "在这个账号的记忆里，你叫",
  "我这里记着的名字是"
], Xr = [
  "。",
  "，对吗？",
  "。如果想换个称呼，也可以告诉我。"
], Zr = [
  "目前你还没有告诉我你的名字。",
  "我这里还没有你的名字呢。愿意的话，可以告诉我怎么称呼你。"
], ei = [
  "好，我记下这条信息：",
  "收到，这条记忆是："
], ti = [
  "之后聊到相关内容时，我会参考它。",
  "这条记忆会保留在当前账号范围内。"
], ni = [
  "这条信息你还没有告诉过我。",
  "我这里还没有这条记忆呢。"
], ri = [
  "",
  "",
  "",
  "",
  "",
  "",
  "🐾",
  "✨"
];
function ae(e, t, n) {
  const r = O(
    ri,
    `${t}:${n}:accent`
  );
  return r.length > 0 ? `${e} ${r}` : e;
}
function ii(e, t) {
  const n = `${e.query.subject}:${e.query.relation}:${e.query.kind}`, r = t.mode !== "no-answer", i = t.isUncertain ? O(Lr, `${n}:hedge`) : void 0;
  if (r)
    return `${O(vr, n)}${t.explanation}${i ?? ""}`;
  const c = O(xr, n), s = O($r, `${n}:closer`);
  return `${c}${t.explanation}${s}`;
}
function ci(e) {
  const t = `${e.subject}:${e.relation}:${e.object}`, n = O(_r, t), r = O(Kr, `${t}:closer`), i = e.negated ? "不" : "", c = `${e.subject} ${i}${e.relation} ${e.object}`;
  return [n, c, r].join(`

`);
}
function si(e) {
  const t = e.raw.trim();
  if (!t)
    return "好像还没有输入内容，可以跟我说点什么。";
  const n = t, r = O(Mr, n), i = O(Pr, `${n}:closer`);
  return `${r}${i}`;
}
function ai(e) {
  const t = e && e.length > 0 ? e : "greeting", n = O(Dr, t);
  return ae(n, "greeting", t);
}
function oi(e) {
  const t = e && e.length > 0 ? e : "thanks", n = O(Ur, t);
  return ae(n, "thanks", t);
}
function ui(e) {
  const t = e && e.length > 0 ? e : "farewell", n = O(qr, t);
  return ae(n, "farewell", t);
}
function li(e) {
  var n;
  const t = new Set(e.candidateLabels);
  if (t.has("identity") && t.has("query"))
    return "这个问题里像是同时问了我的名字和能力，可以分开问我。";
  if (e.focus === "subject" && (((n = e.contextLabels) == null ? void 0 : n.length) ?? 0) >= 2) {
    const r = e.contextLabels ?? [];
    return `你指的是${[
      r.slice(0, -1).join("、"),
      r.at(-1)
    ].join("还是")}呢？可以再确认一下。`;
  }
  return e.focus === "object" && e.relation === "会" ? "你想问我会做什么呢？可以再具体一些。" : e.focus === "object" ? "这里还缺少要说明的内容，可以再告诉我它是什么吗？" : e.focus === "subject" ? "你想问的是谁或什么？可以再补充一点。" : e.focus === "relation" ? "你想了解它哪一方面？可以再说具体一些。" : e.focus === "name" ? "你是在问名字，还是想告诉我你的名字呢？" : t.has("teaching") ? "这条信息还没有说完整，可以再告诉我对象和它们的关系吗？" : "我看到不止一种可能的意思，可以换一种更具体的说法吗？";
}
function fi(e, t, n, r) {
  const i = r && r.length > 0 ? r : `identity:${t}:${e}`;
  if (e === "capability") {
    const l = O(Wr, i), b = O(Vr, `${i}:closer`);
    return `${n.length > 0 ? `${l}${n.map((S) => S.object).join("；")}。` : `关于「${t}」能做什么，我目前还没有明确的答案。`}${b}`;
  }
  if (e === "creator") {
    const l = O(Gr, i), b = O(Yr, `${i}:closer`), [g] = n, S = g ? g.object : "这个我暂时还不清楚。";
    return Pt(l, S, b);
  }
  const c = O(Br, i), s = O(Fr, `${i}:closer`), [a] = n, o = t === "霜蓝" || (a == null ? void 0 : a.subject) === "霜蓝";
  return `${a ? o ? `我就是霜蓝，${a.negated ? "不" : ""}${a.relation} ${a.object}。` : `${c}${a.subject}，${a.negated ? "不" : ""}${a.relation}${a.object}。` : `关于「${t}」，我目前还没有明确的答案。`}${s}`;
}
function di(e, t, n) {
  const r = n && n.length > 0 ? n : `remembered:${e}`;
  if (e === ne.Name) {
    const s = O(Qr, r), a = O(Hr, `${r}:closer`);
    return ae(
      `${s}${t}。${a}`,
      "name-remembered",
      r
    );
  }
  const i = O(ei, r), c = O(ti, `${r}:closer`);
  return Pt(i, t, c);
}
function mi(e, t, n) {
  const r = n && n.length > 0 ? n : `recalled:${e}`;
  if (e === ne.Name) {
    if (t === null)
      return O(Zr, r);
    const i = O(Jr, r), c = O(Xr, `${r}:closer`);
    return ae(
      `${i}${t}${c}`,
      "name-recalled",
      r
    );
  }
  return t === null ? O(ni, r) : t;
}
function bi(e) {
  return "抱歉，我现在遇到了一点问题，请稍后再试一次。";
}
const Fe = {
  id: "frost",
  displayName: "霜蓝 Frost",
  description: "温柔友善、带一点活力的兽圈朋友型人格。默认人格。仅影响语言风格与语气，不改变任何推理结论、置信度或知识内容。",
  respond(e) {
    switch (e.kind) {
      case "reasoning-result":
        return ii(e.result, e.plan);
      case "clarification":
        return li(e.plan);
      case "learned":
        return ci(e.record);
      case "unknown-input":
        return si(e.failure);
      case "greeting":
        return ai(e.raw);
      case "thanks":
        return oi(e.raw);
      case "farewell":
        return ui(e.raw);
      case "identity":
        return fi(e.aspect, e.subject, e.facts, e.raw);
      case "remembered":
        return di(e.key, e.value, e.raw);
      case "recalled":
        return mi(e.key, e.value, e.raw);
      case "error":
        return bi(e.message);
      default: {
        const t = e;
        throw new Error(`Frost: unhandled response context ${JSON.stringify(t)}`);
      }
    }
  }
}, pt = {
  id: "plain",
  displayName: "Plain（无风格 / 调试用）",
  description: "不做任何语言风格修饰的基线人格，仅用于验证人格切换机制与调试输出。",
  respond(e) {
    var t;
    switch (e.kind) {
      case "reasoning-result":
        return e.plan.isUncertain ? `${e.plan.explanation}（不确定）` : e.plan.explanation;
      case "clarification":
        if (e.plan.focus === "subject" && (((t = e.plan.contextLabels) == null ? void 0 : t.length) ?? 0) >= 2) {
          const n = e.plan.contextLabels ?? [];
          return `你指的是${[
            n.slice(0, -1).join("、"),
            n.at(-1)
          ].join("还是")}？请再说明一下。`;
        }
        return e.plan.focus === "object" && e.plan.relation === "会" ? "你想问会做什么？请再具体一点。" : e.plan.focus === "object" ? "缺少要说明的内容，请补充完整。" : e.plan.focus === "subject" ? "缺少要询问的对象，请补充完整。" : e.plan.focus === "relation" ? "缺少要询问的方面，请补充完整。" : e.plan.focus === "name" ? "请说明你是在询问名字，还是提供名字。" : "这句话有多种可能的意思，请换一种更具体的说法。";
      case "learned": {
        const n = e.record.negated ? "不" : "";
        return `已记录：${e.record.subject} ${n}${e.record.relation} ${e.record.object}`;
      }
      case "unknown-input":
        return e.failure.raw.trim() ? "这个问题我暂时还没理解清楚。你可以换一种说法，或者再告诉我一点相关信息。" : "好像还没有输入内容呢，可以跟我说点什么。";
      case "greeting":
        return "你好。";
      case "thanks":
        return "不客气。";
      case "farewell":
        return "再见。";
      case "identity": {
        const [n] = e.facts;
        if (!n) return `未知：关于 ${e.subject}（${e.aspect}）`;
        const r = n.negated ? "不" : "";
        return `${n.subject} ${r}${n.relation} ${n.object}`;
      }
      case "remembered":
        return `已记住：${e.key} = ${e.value}`;
      case "recalled":
        return e.value === null ? `未知：${e.key}` : `${e.key} = ${e.value}`;
      case "error":
        return "暂时无法完成这次请求，请稍后再试。";
      default: {
        const n = e;
        throw new Error(`Plain: unhandled response context ${JSON.stringify(n)}`);
      }
    }
  }
}, gi = Fe.id, re = /* @__PURE__ */ new Map();
function hi() {
  re.set(Fe.id, Fe), re.set(pt.id, pt);
}
hi();
function Ca(e) {
  re.set(e.id, e);
}
function Ra() {
  return Array.from(re.values());
}
function pi(e = gi) {
  const t = re.get(e);
  if (!t)
    throw new Error(`getPersonality: unknown personality id "${e}"`);
  return t;
}
const ji = 0.75;
function Dt(e) {
  const { subject: t, relation: n, object: r, negated: i } = e.conclusion;
  return `${t} ${i ? "不" : ""}${n} ${r}`;
}
function yi(e) {
  const t = Dt(e);
  return e.steps.length === 0 ? t : `${t}（推理路径：${e.path.join(" → ")}）`;
}
function Oi(e) {
  return Math.min(...e.map((t) => t.confidence));
}
const Si = Object.freeze([
  "subject",
  "relation",
  "object",
  "name",
  "intent"
]);
function Ei(e) {
  for (const t of Si)
    if (e.missingSlots.includes(t)) return t;
  return e.clarificationKind === "uncertain-name" ? "name" : "intent";
}
const jt = {
  id: "default-v1",
  plan(e) {
    const { answers: t, query: n } = e;
    if (t.length === 0)
      return {
        mode: "no-answer",
        showEvidence: !1,
        isUncertain: !1,
        confidence: 0,
        explanation: e.explanation
      };
    const r = n.explain === !0, i = Oi(t);
    return {
      mode: r ? "explained" : "direct",
      showEvidence: r,
      isUncertain: i < ji,
      confidence: i,
      explanation: (r ? t.map(yi) : t.map(Dt)).join("；")
    };
  },
  planClarification(e) {
    return Object.freeze({
      clarificationKind: e.clarificationKind,
      focus: Ei(e),
      candidateLabels: Object.freeze([...e.candidateLabels]),
      reasonCategory: e.reasonCategory,
      ...e.relation === void 0 ? {} : { relation: e.relation },
      ...e.contextLabels === void 0 ? {} : {
        contextLabels: Object.freeze([
          ...e.contextLabels
        ])
      }
    });
  }
}, wi = "isa-transitivity";
function Ci(e) {
  const t = [];
  let n = {
    subject: e[0].subject,
    relation: p.IsA,
    object: e[0].object,
    negated: !1
  };
  for (let r = 1; r < e.length; r += 1) {
    const i = e[r], c = {
      subject: n.subject,
      relation: p.IsA,
      object: i.object,
      negated: !1
    };
    t.push({
      ruleId: wi,
      description: `${n.subject} 属于 ${n.object}，${i.subject} 属于 ${i.object} ⇒ ${c.subject} 属于 ${c.object}`,
      premises: [n, { subject: i.subject, relation: p.IsA, object: i.object, negated: !1 }],
      conclusion: c
    }), n = c;
  }
  return t;
}
function yt(e) {
  const t = e[0].subject, n = e[e.length - 1].object, r = [t, ...e.map((c) => c.object)], i = e.reduce((c, s) => c * s.confidence, 1);
  return {
    conclusion: { subject: t, relation: p.IsA, object: n, negated: !1 },
    confidence: i,
    steps: Ci(e),
    path: r
  };
}
function Ri(e, t) {
  const n = /* @__PURE__ */ new Set([t.subject]), r = [
    { node: t.subject, records: [] }
  ], i = [];
  let c = 0;
  for (; c < r.length; ) {
    const s = r[c];
    c += 1;
    const a = e.match({
      subject: s.node,
      relation: p.IsA,
      negated: !1
    });
    for (const o of a) {
      if (n.has(o.object)) continue;
      n.add(o.object);
      const d = [...s.records, o];
      if (t.targetObject === o.object)
        return d.length >= 2 ? [yt(d)] : [];
      r.push({
        node: o.object,
        records: d
      }), t.targetObject === void 0 && d.length >= 2 && i.push(yt(d));
    }
  }
  return i;
}
const ki = "relation-alignment-v1", zi = Object.freeze([
  Object.freeze({
    queriedRelation: p.Is,
    matchedRelation: p.IsA,
    legacyClassificationOnly: !1
  }),
  Object.freeze({
    queriedRelation: p.IsA,
    matchedRelation: p.Is,
    legacyClassificationOnly: !0
  })
]), Ut = Object.freeze({
  id: ki,
  fallbackFor(e, t = {}) {
    return e.kind !== "object-of" || e.object !== void 0 || t.contextResolved === !0 || t.negatedInput === !0 ? null : zi.find(
      ({ queriedRelation: n }) => n === e.relation
    ) ?? null;
  }
});
function xe(e, t, n, r = Ut) {
  return Object.freeze({
    mode: e,
    queriedRelation: t,
    matchedRelation: n,
    policyId: r.id
  });
}
const Ii = "目前还没有已知的相关事实。";
function Ni(e, t) {
  return t.match({
    subject: e.subject,
    relation: e.relation,
    ...e.object !== void 0 ? { object: e.object } : {}
  }).map((r) => ({
    conclusion: { subject: r.subject, relation: r.relation, object: r.object, negated: r.negated },
    confidence: r.confidence,
    steps: [],
    path: [r.subject, r.object]
  }));
}
function Ti(e, t) {
  return e.relation !== p.IsA ? [] : Ri(t, {
    subject: e.subject,
    ...e.object === void 0 ? {} : { targetObject: e.object }
  });
}
function Ai(e) {
  const { subject: t, relation: n, object: r, negated: i } = e.conclusion, c = i ? "不" : "";
  return e.steps.length === 0 ? `${t} ${c}${n} ${r}` : `${t} ${c}${n} ${r}（推理路径：${e.path.join(" → ")}）`;
}
function We(e, t) {
  const n = t.length > 0 ? t.map(Ai).join("；") : Ii;
  return {
    query: e,
    answers: t,
    conflicts: [],
    explanation: n
  };
}
function Ot(e, t) {
  const n = Ni(e, t);
  if (e.object !== void 0 && n.length > 0)
    return We(e, n);
  const r = new Set(
    n.map((c) => c.conclusion.object)
  ), i = Ti(e, t).filter(
    (c) => !r.has(c.conclusion.object)
  );
  return We(e, [...n, ...i]);
}
function vi(e) {
  if (e.negated || !e.object.startsWith("一种"))
    return null;
  const t = e.object.slice(2).trim();
  return t.length > 0 ? t : null;
}
function xi(e, t) {
  const n = [];
  for (const r of t.match({
    subject: e.subject,
    relation: p.Is,
    negated: !1
  })) {
    const i = vi(r);
    i !== null && n.push({
      conclusion: {
        subject: r.subject,
        relation: p.IsA,
        object: i,
        negated: !1
      },
      confidence: r.confidence,
      steps: [],
      path: [r.subject, i]
    });
  }
  return n;
}
function $i(e, t, n = {}, r = Ut) {
  const i = Ot(e, t);
  if (i.answers.length > 0)
    return Object.freeze({
      result: i,
      relationResolution: xe(
        "exact",
        e.relation,
        e.relation,
        r
      )
    });
  const c = r.fallbackFor(e, n);
  if (c === null)
    return Object.freeze({
      result: i,
      relationResolution: xe(
        "exact",
        e.relation,
        e.relation,
        r
      )
    });
  const s = c.legacyClassificationOnly ? xi(e, t) : Ot(
    {
      ...e,
      relation: c.matchedRelation
    },
    t
  ).answers;
  return Object.freeze({
    result: We(e, s),
    relationResolution: xe(
      "fallback",
      e.relation,
      c.matchedRelation,
      r
    )
  });
}
function tt(e) {
  return e !== null && Number.isFinite(e) && e >= 0;
}
function $e(e) {
  return tt(e) ? e < 1 ? "under-1ms" : e < 5 ? "1-5ms" : e < 16 ? "5-16ms" : e < 50 ? "16-50ms" : "over-50ms" : "unavailable";
}
function Li(e) {
  return !tt(e) || !Number.isSafeInteger(e) ? "unavailable" : e === 0 ? "0" : e < 100 ? "1-99" : e < 1e3 ? "100-999" : e < 5e3 ? "1000-4999" : "5000-plus";
}
function _i(e) {
  return !tt(e) || !Number.isSafeInteger(e) ? "unavailable" : e === 0 ? "none" : e === 1 ? "direct" : e <= 5 ? "2-5" : e <= 20 ? "6-20" : e <= 50 ? "21-50" : "51-plus";
}
const qt = "0.1.0", Bt = 1, Ft = 1, Wt = 1, Ki = Object.freeze([
  "understood",
  "clarification",
  "no-understanding",
  "missing-knowledge",
  "relation-unsupported",
  "context-unresolved",
  "side-effect-blocked",
  "safe-fallback"
]), Mi = Object.freeze([
  "complete-passive-understanding",
  "missing-subject",
  "missing-relation",
  "missing-object",
  "ambiguous-intent",
  "conflicting-candidates",
  "insufficient-evidence",
  "missing-knowledge",
  "unsupported-relation",
  "unresolved-context",
  "blocked-side-effect",
  "semantic-runtime",
  "reasoner-error",
  "unknown-safe-fallback",
  "unclassified"
]), Pi = Object.freeze([
  "属于",
  "是",
  "会",
  "喜欢",
  "在",
  "有",
  "意思是",
  "开发者",
  "none",
  "unknown"
]), Di = Object.freeze([
  "ambiguous-intent",
  "missing-subject",
  "missing-relation",
  "missing-object",
  "uncertain-name",
  "uncertain-teaching",
  "conflicting-candidates",
  "none"
]), Ui = Object.freeze([
  "under-1ms",
  "1-5ms",
  "5-16ms",
  "16-50ms",
  "over-50ms",
  "unavailable"
]), qi = Object.freeze([
  "0",
  "1-99",
  "100-999",
  "1000-4999",
  "5000-plus",
  "unavailable"
]), Bi = Object.freeze([
  "direct",
  "2-5",
  "6-20",
  "21-50",
  "51-plus",
  "none",
  "unavailable"
]), Fi = Object.freeze([
  "aligned",
  "possible-mismatch",
  "no-alternative-known",
  "unavailable"
]), Ve = Object.freeze([
  "schemaVersion",
  "sunlandCoreVersion",
  "semanticSchemaVersion",
  "contextSchemaVersion",
  "resultCategory",
  "reasonCategory",
  "relationCategory",
  "semanticAdopted",
  "legacyFallback",
  "contextUsed",
  "clarificationKind",
  "pathLengthBucket",
  "knowledgeCountBucket",
  "totalDurationBucket",
  "semanticDurationBucket",
  "reasonerDurationBucket",
  "queriedRelation",
  "alternativeKnownRelation",
  "alignmentResult"
]), Vt = new Set(
  Ki
), Gt = new Set(
  Mi
), Y = new Set(
  Pi
), Yt = new Set(
  Di
), Wi = new Set(Bi), Vi = new Set(
  qi
), Le = new Set(Ui), Qt = new Set(
  Fi
);
function Gi(e) {
  return typeof e == "object" && e !== null;
}
function z(e, t) {
  return typeof e == "string" && t.has(e);
}
function Yi(e) {
  const t = Reflect.ownKeys(e);
  return t.length === Ve.length && t.every(
    (n) => typeof n == "string" && Ve.includes(n)
  );
}
function Qi(e) {
  return Ve.every((t) => {
    const n = Object.getOwnPropertyDescriptor(e, t);
    return n !== void 0 && "value" in n && n.get === void 0 && n.set === void 0;
  });
}
function Hi(e) {
  return Object.freeze({
    schemaVersion: Wt,
    sunlandCoreVersion: qt,
    semanticSchemaVersion: Bt,
    contextSchemaVersion: Ft,
    resultCategory: Vt.has(e.resultCategory) ? e.resultCategory : "safe-fallback",
    reasonCategory: Gt.has(e.reasonCategory) ? e.reasonCategory : "unclassified",
    relationCategory: Y.has(e.relationCategory) ? e.relationCategory : "unknown",
    semanticAdopted: e.semanticAdopted === !0,
    legacyFallback: e.legacyFallback === !0,
    contextUsed: e.contextUsed === !0,
    clarificationKind: Yt.has(
      e.clarificationKind
    ) ? e.clarificationKind : "none",
    pathLengthBucket: _i(
      e.reasonerPathLength
    ),
    knowledgeCountBucket: Li(
      e.knowledgeCount
    ),
    totalDurationBucket: $e(e.totalDurationMs),
    semanticDurationBucket: $e(
      e.semanticDurationMs
    ),
    reasonerDurationBucket: $e(
      e.reasonerDurationMs
    ),
    queriedRelation: Y.has(e.queriedRelation) ? e.queriedRelation : "unknown",
    alternativeKnownRelation: Y.has(
      e.alternativeKnownRelation
    ) ? e.alternativeKnownRelation : "unknown",
    alignmentResult: Qt.has(e.alignmentResult) ? e.alignmentResult : "unavailable"
  });
}
function Ji(e) {
  try {
    return !Gi(e) || !Yi(e) || !Qi(e) ? !1 : e.schemaVersion === Wt && e.sunlandCoreVersion === qt && e.semanticSchemaVersion === Bt && e.contextSchemaVersion === Ft && z(e.resultCategory, Vt) && z(e.reasonCategory, Gt) && z(e.relationCategory, Y) && typeof e.semanticAdopted == "boolean" && typeof e.legacyFallback == "boolean" && typeof e.contextUsed == "boolean" && z(e.clarificationKind, Yt) && z(e.pathLengthBucket, Wi) && z(
      e.knowledgeCountBucket,
      Vi
    ) && z(
      e.totalDurationBucket,
      Le
    ) && z(
      e.semanticDurationBucket,
      Le
    ) && z(
      e.reasonerDurationBucket,
      Le
    ) && z(e.queriedRelation, Y) && z(
      e.alternativeKnownRelation,
      Y
    ) && z(e.alignmentResult, Qt);
  } catch {
    return !1;
  }
}
function Xi(e) {
  return Ji(e) ? Object.freeze({
    schemaVersion: e.schemaVersion,
    sunlandCoreVersion: e.sunlandCoreVersion,
    semanticSchemaVersion: e.semanticSchemaVersion,
    contextSchemaVersion: e.contextSchemaVersion,
    resultCategory: e.resultCategory,
    reasonCategory: e.reasonCategory,
    relationCategory: e.relationCategory,
    semanticAdopted: e.semanticAdopted,
    legacyFallback: e.legacyFallback,
    contextUsed: e.contextUsed,
    clarificationKind: e.clarificationKind,
    pathLengthBucket: e.pathLengthBucket,
    knowledgeCountBucket: e.knowledgeCountBucket,
    totalDurationBucket: e.totalDurationBucket,
    semanticDurationBucket: e.semanticDurationBucket,
    reasonerDurationBucket: e.reasonerDurationBucket,
    queriedRelation: e.queriedRelation,
    alternativeKnownRelation: e.alternativeKnownRelation,
    alignmentResult: e.alignmentResult
  }) : null;
}
function Zi(e) {
  return typeof e == "number" && Number.isFinite(e) && e >= 0 && e <= 1;
}
function T(e) {
  if (!Zi(e))
    throw new RangeError("Confidence must be a finite number between 0 and 1.");
  return e;
}
function ec(e) {
  return Object.freeze({
    ...e,
    aliases: Object.freeze([...e.aliases]),
    baseWeight: T(e.baseWeight),
    constraints: Object.freeze({
      ...e.constraints,
      allowedCandidateKinds: Object.freeze([
        ...e.constraints.allowedCandidateKinds
      ])
    })
  });
}
const tc = Object.freeze(
  [
    {
      id: "greeting",
      canonical: "你好",
      aliases: ["你好", "您好", "嗨", "哈喽", "hello", "hi", "hey"],
      category: "conversation",
      baseWeight: 0.92,
      constraints: {
        matchMode: "whole-input",
        allowedCandidateKinds: ["intent"]
      },
      sideEffectSafe: !1
    },
    {
      id: "thanks",
      canonical: "谢谢",
      aliases: ["谢谢", "谢了", "感谢", "多谢", "thanks", "thank you", "thx"],
      category: "conversation",
      baseWeight: 0.92,
      constraints: {
        matchMode: "whole-input",
        allowedCandidateKinds: ["intent"]
      },
      sideEffectSafe: !1
    },
    {
      id: "goodbye",
      canonical: "再见",
      aliases: ["再见", "拜拜", "先走", "bye", "goodbye", "see you"],
      category: "conversation",
      baseWeight: 0.92,
      constraints: {
        matchMode: "whole-input",
        allowedCandidateKinds: ["intent"]
      },
      sideEffectSafe: !1
    },
    {
      id: "identity-name",
      canonical: "你叫什么",
      aliases: ["你叫什么", "你叫啥", "你的名字是什么"],
      category: "identity",
      baseWeight: 0.94,
      constraints: {
        matchMode: "whole-input",
        allowedCandidateKinds: ["query"]
      },
      sideEffectSafe: !1
    },
    {
      id: "identity-self",
      canonical: "你是谁",
      aliases: [
        "你是谁",
        "你是什么",
        "sunland ai是什么",
        "sunland ai 是什么"
      ],
      category: "identity",
      baseWeight: 0.94,
      constraints: {
        matchMode: "whole-input",
        allowedCandidateKinds: ["query"]
      },
      sideEffectSafe: !1
    },
    {
      id: "remember-name",
      canonical: "我叫",
      aliases: ["我叫", "我的名字是", "你可以叫我", "叫我"],
      category: "memory",
      baseWeight: 0.9,
      constraints: {
        matchMode: "prefix",
        allowedCandidateKinds: ["statement"],
        requiresFollowingEntity: !0
      },
      sideEffectSafe: !0
    },
    {
      id: "recall-name",
      canonical: "我叫什么",
      aliases: [
        "我叫什么",
        "我叫什么名字",
        "你记得我叫什么吗",
        "你记得我的名字吗",
        "你还记得我的名字吗",
        "还记得我是谁吗"
      ],
      category: "memory",
      baseWeight: 0.93,
      constraints: {
        matchMode: "whole-input",
        allowedCandidateKinds: ["query"]
      },
      sideEffectSafe: !1
    },
    {
      id: "teaching",
      canonical: "教你",
      aliases: ["教你", "告诉你一个知识", "记住这个事实"],
      category: "knowledge",
      baseWeight: 0.82,
      constraints: {
        matchMode: "prefix",
        allowedCandidateKinds: ["statement"],
        requiresFollowingEntity: !0
      },
      sideEffectSafe: !0
    },
    {
      id: "query-definition",
      canonical: "是什么",
      aliases: ["是什么", "是啥", "指什么", "什么意思"],
      category: "knowledge",
      baseWeight: 0.84,
      constraints: {
        matchMode: "infix",
        allowedCandidateKinds: ["query"]
      },
      sideEffectSafe: !1
    },
    {
      id: "is-a",
      canonical: "属于",
      aliases: ["属于", "是一种", "算是", "归类为", "是"],
      category: "relation",
      baseWeight: 0.86,
      constraints: {
        matchMode: "infix",
        allowedCandidateKinds: ["statement", "query"]
      },
      sideEffectSafe: !0
    },
    {
      id: "can",
      canonical: "会",
      aliases: ["会", "能", "能够"],
      category: "relation",
      baseWeight: 0.78,
      constraints: {
        matchMode: "infix",
        allowedCandidateKinds: ["statement", "query"]
      },
      sideEffectSafe: !0
    },
    {
      id: "has",
      canonical: "有",
      aliases: ["有", "拥有", "具备"],
      category: "relation",
      baseWeight: 0.8,
      constraints: {
        matchMode: "infix",
        allowedCandidateKinds: ["statement", "query"]
      },
      sideEffectSafe: !0
    },
    {
      id: "means",
      canonical: "意思是",
      aliases: ["意思是", "是什么意思", "表示", "指的是"],
      category: "relation",
      baseWeight: 0.84,
      constraints: {
        matchMode: "infix",
        allowedCandidateKinds: ["statement", "query"]
      },
      sideEffectSafe: !0
    }
  ].map(ec)
), nc = Object.freeze({
  "，": ",",
  "。": ".",
  "？": "?",
  "！": "!",
  "；": ";",
  "：": ":",
  "（": "(",
  "）": ")",
  "【": "[",
  "】": "]",
  "“": '"',
  "”": '"',
  "‘": "'",
  "’": "'",
  "～": "~"
}), rc = /* @__PURE__ */ new Set(["嗯", "呃", "唔"]), ic = /* @__PURE__ */ new Set(["呀", "啊", "呢", "哦", "啦"]), cc = /[\s,.;:!?'"()[\]~]/u;
function M(e, t) {
  return Object.freeze({ start: e, end: t });
}
function Q(e) {
  return Object.freeze({
    ...e,
    rawRange: Object.freeze({ ...e.rawRange })
  });
}
function sc(e) {
  const t = [];
  let n = 0;
  for (const r of e) {
    const i = n;
    n += r.length, t.push(
      Object.freeze({
        text: r,
        rawRange: M(i, n)
      })
    );
  }
  return t;
}
function ac(e, t) {
  const n = sc(e), r = [];
  let i = 0;
  for (; i < n.length; ) {
    const c = n[i];
    if (/\s/u.test(c.text)) {
      const a = i;
      let o = i + 1;
      for (; o < n.length && /\s/u.test(n[o].text); )
        o += 1;
      const d = n.slice(a, o), l = M(
        d[0].rawRange.start,
        d[d.length - 1].rawRange.end
      ), b = e.slice(l.start, l.end);
      a === 0 || o === n.length ? t.push(
        Q({
          stage: "surface",
          kind: "whitespace-trimmed",
          rawRange: l,
          sourceText: b,
          targetText: ""
        })
      ) : (r.push(Object.freeze({ text: " ", rawRange: l })), b !== " " && t.push(
        Q({
          stage: "surface",
          kind: "whitespace-collapsed",
          rawRange: l,
          sourceText: b,
          targetText: " "
        })
      )), i = o;
      continue;
    }
    const s = nc[c.text];
    s !== void 0 ? (r.push(
      Object.freeze({
        text: s,
        rawRange: c.rawRange
      })
    ), t.push(
      Q({
        stage: "surface",
        kind: "punctuation-normalized",
        rawRange: c.rawRange,
        sourceText: c.text,
        targetText: s
      })
    )) : r.push(c), i += 1;
  }
  return r;
}
function be(e) {
  return e !== void 0 && cc.test(e.text);
}
function oc(e, t) {
  let n = 0, r = e.length;
  for (; n < r && rc.has(e[n].text) && be(e[n + 1]); ) {
    const i = e[n];
    let c = n + 1;
    for (; c < r && be(e[c]); )
      c += 1;
    const s = e.slice(n, c), a = M(
      i.rawRange.start,
      s[s.length - 1].rawRange.end
    );
    t.push(
      Q({
        stage: "match-key",
        kind: "edge-filler-removed",
        rawRange: a,
        sourceText: s.map((o) => o.text).join(""),
        targetText: ""
      })
    ), n = c;
  }
  for (; r > n && ic.has(e[r - 1].text) && be(e[r - 2]); ) {
    const i = e[r - 1];
    let c = r - 1;
    for (; c > n && be(e[c - 1]); )
      c -= 1;
    const s = e.slice(c, r), a = M(
      s[0].rawRange.start,
      i.rawRange.end
    );
    t.push(
      Q({
        stage: "match-key",
        kind: "edge-filler-removed",
        rawRange: a,
        sourceText: s.map((o) => o.text).join(""),
        targetText: ""
      })
    ), r = c;
  }
  return e.slice(n, r);
}
function uc(e, t) {
  const n = oc(
    e,
    t
  ), r = [];
  for (const i of n) {
    const c = i.text.toLocaleLowerCase("und");
    r.push(Object.freeze({ text: c, rawRange: i.rawRange })), c !== i.text && t.push(
      Q({
        stage: "match-key",
        kind: "case-folded",
        rawRange: i.rawRange,
        sourceText: i.text,
        targetText: c
      })
    );
  }
  return r;
}
function St(e) {
  const t = [];
  let n = "";
  for (const r of e) {
    n += r.text;
    for (let i = 0; i < r.text.length; i += 1)
      t.push(r.rawRange);
  }
  return Object.freeze({
    text: n,
    mapping: Object.freeze(t)
  });
}
function lc(e) {
  const t = [], n = ac(e, t), r = uc(n, t), i = St(n), c = St(r);
  return Object.freeze({
    raw: e,
    surface: i.text,
    matchKey: c.text,
    surfaceToRaw: i.mapping,
    matchKeyToRaw: c.mapping,
    transformations: Object.freeze(t)
  });
}
function D(e, t, n, r) {
  const i = t === "surface" ? e.surface : e.matchKey, c = t === "surface" ? e.surfaceToRaw : e.matchKeyToRaw;
  if (!Number.isInteger(n) || !Number.isInteger(r) || n < 0 || r < n || r > i.length)
    throw new RangeError(
      `Normalized range must be within ${t} UTF-16 bounds.`
    );
  if (n === r) {
    if (n < c.length)
      return M(c[n].start, c[n].start);
    if (c.length > 0) {
      const o = c[c.length - 1];
      return M(o.end, o.end);
    }
    return M(0, 0);
  }
  let s = c[n].start, a = c[n].end;
  for (let o = n + 1; o < r; o += 1)
    s = Math.min(s, c[o].start), a = Math.max(a, c[o].end);
  return M(s, a);
}
const h = T, m = Object.freeze({
  producerWeight: Object.freeze({
    "legacy-regex": h(0.9),
    lexicon: h(0.8),
    "relation-pattern": h(0.72),
    context: h(0.64)
  }),
  legacy: Object.freeze({
    unknown: h(0.08),
    statement: h(0.91),
    query: h(0.92),
    intentFloor: h(0.88)
  }),
  lexicon: Object.freeze({
    aliasWeightShare: h(0.82),
    coverageWeightShare: h(0.18),
    exactInputBonus: h(0.04),
    entityCompleteBonus: h(0.08),
    sideEffectPenalty: h(0.03)
  }),
  relation: Object.freeze({
    base: h(0.48),
    conceptWeightShare: h(0.2),
    subjectBonus: h(0.12),
    objectBonus: h(0.12),
    queryShapeBonus: h(0.12),
    statementShapeBonus: h(0.14),
    missingSlotPenalty: h(0.16),
    sideEffectPenalty: h(0.05),
    weakSingleCharacterPenalty: h(0.08)
  }),
  context: Object.freeze({
    resolvedQuery: h(0.86),
    unresolvedReference: h(0.48),
    inheritedSubject: h(0.14),
    inheritedRelation: h(0.12)
  }),
  feature: Object.freeze({
    directSelf: h(0.9),
    indirectSelf: h(0.7),
    explicitName: h(0.94),
    questionCue: h(0.75),
    negationCue: h(0.9),
    structuralTeaching: h(0.68),
    definitionQuery: h(0.84)
  }),
  producerTieBreak: Object.freeze({
    "legacy-regex": 0,
    lexicon: 1,
    "relation-pattern": 2,
    context: 3
  })
});
function je(e) {
  return T(Math.min(1, Math.max(0, e)));
}
function we(e, t = [], n = []) {
  const r = t.reduce((c, s) => c + s, 0), i = n.reduce((c, s) => c + s, 0);
  return je(e + r - i);
}
function fc(e, t, n, r) {
  const i = n.length === 0 ? 0 : Math.min(1, t.length / n.length), c = e * m.lexicon.aliasWeightShare + i * m.lexicon.coverageWeightShare;
  return we(
    c,
    r ? [m.lexicon.exactInputBonus] : []
  );
}
const dc = Object.freeze(
  [
    "为什么",
    "有没有",
    "是不是",
    "会不会",
    "还是",
    "什么",
    "啥",
    "谁",
    "哪里",
    "哪",
    "怎么",
    "吗",
    "?"
  ].map(
    (e) => Object.freeze({
      value: e,
      kind: "question-cue",
      key: `question:${e}`
    })
  )
), mc = Object.freeze(
  ["不是", "不会", "不能", "没有", "不", "没", "别"].map(
    (e) => Object.freeze({
      value: e,
      kind: "negation-cue",
      key: `negation:${e}`
    })
  )
), bc = Object.freeze([
  Object.freeze({
    value: "sunland ai",
    canonical: "Sunland AI · Beta",
    confidence: m.feature.directSelf
  }),
  Object.freeze({
    value: "你",
    canonical: "Sunland AI · Beta",
    confidence: m.feature.directSelf
  }),
  Object.freeze({
    value: "霜蓝",
    canonical: "霜蓝",
    confidence: m.feature.indirectSelf
  })
]), gc = /* @__PURE__ */ new Set(["is-a", "can", "has", "means"]), hc = /* @__PURE__ */ new Set(["什么", "什么名字", "谁", "吗"]), Ge = /[a-z0-9]/iu, Ye = /[\s,.;:!?'"()[\]~]/u;
function nt(e, t) {
  return Object.freeze({ start: e, end: t });
}
function ie(e, t, n, r, i) {
  return Object.freeze({
    kind: e,
    key: t,
    value: n,
    rawRange: Object.freeze({ ...r }),
    weight: i
  });
}
function Et(e, t) {
  return t < 0 || t >= e.length ? !0 : !Ge.test(e[t]);
}
function Ht(e, t, n, r) {
  const i = t[0], c = t[t.length - 1], s = i === void 0 || !Ge.test(i) || Et(e, n - 1), a = c === void 0 || !Ge.test(c) || Et(e, r);
  return s && a;
}
function Jt(e, t) {
  return e.start < t.end && t.start < e.end;
}
function pc(e) {
  const t = [];
  for (const n of tc) {
    const r = [], i = [...n.aliases].sort(
      (s, a) => a.length - s.length || s.localeCompare(a)
    );
    for (const s of i) {
      const a = s.trim().replace(/\s+/gu, " ").toLocaleLowerCase("und");
      let o = 0;
      for (; a.length > 0; ) {
        const d = e.matchKey.indexOf(a, o);
        if (d < 0)
          break;
        const l = d + a.length;
        if (o = d + 1, !Ht(e.matchKey, a, d, l))
          continue;
        const b = D(
          e,
          "matchKey",
          d,
          l
        ), g = fc(
          n.baseWeight,
          a,
          e.matchKey,
          e.matchKey === a
        ), S = ie(
          "lexicon-alias",
          n.id,
          s,
          b,
          g
        ), R = Object.freeze({
          id: n.id,
          canonical: n.canonical,
          matchedAlias: s,
          confidence: g,
          evidence: Object.freeze([S])
        });
        r.push(
          Object.freeze({
            entry: n,
            alias: s,
            start: d,
            end: l,
            rawRange: b,
            feature: S,
            concept: R
          })
        );
      }
    }
    r.sort(
      (s, a) => s.start - a.start || a.end - a.start - (s.end - s.start) || s.alias.localeCompare(a.alias)
    );
    const c = [];
    for (const s of r)
      c.some((a) => Jt(a, s)) || c.push(s);
    t.push(...c);
  }
  return Object.freeze(
    t.sort(
      (n, r) => n.start - r.start || n.end - r.end || n.entry.id.localeCompare(r.entry.id)
    )
  );
}
function wt(e, t, n) {
  const r = [], i = [...t].sort(
    (c, s) => s.value.length - c.value.length
  );
  for (const c of i) {
    let s = 0;
    for (; c.value.length > 0; ) {
      const a = e.matchKey.indexOf(c.value, s);
      if (a < 0)
        break;
      const o = a + c.value.length;
      if (s = a + 1, r.some(
        (l) => a < l.end && l.start < o
      ))
        continue;
      const d = D(
        e,
        "matchKey",
        a,
        o
      );
      r.push(
        Object.freeze({
          start: a,
          end: o,
          feature: ie(
            c.kind,
            c.key,
            c.value,
            d,
            n
          )
        })
      );
    }
  }
  return Object.freeze(
    r.sort(
      (c, s) => c.start - s.start || c.end - s.end
    ).map((c) => c.feature)
  );
}
function jc(e, t, n) {
  let r = t, i = n;
  for (; r < i && Ye.test(e[r]); )
    r += 1;
  for (; i > r && Ye.test(e[i - 1]); )
    i -= 1;
  return nt(r, i);
}
function rt(e, t, n, r, i, c) {
  const s = D(
    e,
    "matchKey",
    r,
    i
  );
  return Object.freeze({
    kind: t,
    value: n,
    rawText: e.raw.slice(s.start, s.end),
    start: s.start,
    end: s.end,
    source: "explicit",
    confidence: c
  });
}
function yc(e) {
  const t = [];
  for (const n of bc) {
    let r = 0;
    for (; n.value.length > 0; ) {
      const i = e.matchKey.indexOf(n.value, r);
      if (i < 0)
        break;
      const c = i + n.value.length;
      r = c, Ht(
        e.matchKey,
        n.value,
        i,
        c
      ) && t.push(
        rt(
          e,
          "self",
          n.canonical,
          i,
          c,
          n.confidence
        )
      );
    }
  }
  return Object.freeze(t);
}
function Oc(e, t) {
  const n = [];
  for (const r of t) {
    if (r.entry.id !== "remember-name")
      continue;
    let i = r.end, c = e.matchKey.length;
    for (; i < c && Ye.test(e.matchKey[i]); )
      i += 1;
    const s = e.matchKey.slice(i).search(/[,;!?]/u);
    s >= 0 && (c = i + s);
    const a = jc(e.matchKey, i, c);
    if (a.start >= a.end)
      continue;
    const o = D(
      e,
      "matchKey",
      a.start,
      a.end
    ), d = e.raw.slice(o.start, o.end).trim().replace(/\s+/gu, " "), l = d.toLocaleLowerCase("und");
    d.length === 0 || hc.has(l) || /^(?:不|没|别)/u.test(l) || n.push(
      rt(
        e,
        "person-name",
        d,
        a.start,
        a.end,
        m.feature.explicitName
      )
    );
  }
  return Object.freeze(
    n.filter(
      (r, i) => n.findIndex(
        (c) => c.start === r.start && c.end === r.end && c.value === r.value
      ) === i
    )
  );
}
function Sc(e, t) {
  const n = t.filter(
    (i) => gc.has(i.entry.id)
  ).sort(
    (i, c) => i.start - c.start || c.end - c.start - (i.end - i.start) || i.entry.id.localeCompare(c.entry.id)
  ), r = [];
  for (const i of n)
    r.some((c) => Jt(c, i)) || r.push(i);
  return Object.freeze(
    r.map((i) => {
      const c = rt(
        e,
        "relation",
        i.entry.canonical,
        i.start,
        i.end,
        i.concept.confidence
      );
      return Object.freeze({
        conceptId: i.entry.id,
        canonical: i.entry.canonical,
        alias: i.alias,
        matchKeyRange: nt(i.start, i.end),
        entity: c,
        confidence: i.concept.confidence,
        evidence: Object.freeze([i.feature])
      });
    })
  );
}
function Ec(e, t) {
  return t.length > 0 ? Object.freeze([]) : Object.freeze(
    e.map(
      (n) => ie(
        "teaching-cue",
        `teaching:${n.conceptId}`,
        n.alias,
        nt(n.entity.start, n.entity.end),
        m.feature.structuralTeaching
      )
    )
  );
}
function wc(e) {
  const t = pc(e), n = Object.freeze(
    t.map((g) => g.concept)
  ), r = wt(
    e,
    dc,
    m.feature.questionCue
  ), i = wt(
    e,
    mc,
    m.feature.negationCue
  ), c = yc(e), s = Oc(e, t), a = Sc(e, t), o = t.filter((g) => g.entry.id === "teaching").map(
    (g) => ie(
      "teaching-cue",
      "teaching:explicit",
      g.alias,
      g.rawRange,
      g.concept.confidence
    )
  ), d = Object.freeze([
    ...o,
    ...Ec(a, r)
  ]), l = Object.freeze(
    t.filter((g) => g.entry.id === "query-definition").map(
      (g) => ie(
        "definition-query",
        "query:definition",
        g.alias,
        g.rawRange,
        m.feature.definitionQuery
      )
    )
  ), b = Object.freeze([
    ...c,
    ...s,
    ...a.map((g) => g.entity)
  ]);
  return Object.freeze({
    input: e,
    concepts: n,
    entities: b,
    questionCues: r,
    negationCues: i,
    selfReferences: c,
    personNames: s,
    relations: a,
    teachingCues: d,
    definitionQueryCues: l
  });
}
const N = Object.freeze({
  maximumTurns: 6,
  maximumConceptsPerTurn: 8,
  maximumEntitiesPerTurn: 4,
  maximumEntityValueLength: 80,
  maximumRelationLength: 48,
  maximumTurnIdLength: 128
}), Cc = /* @__PURE__ */ new Set([
  "Greeting",
  "Thanks",
  "Farewell",
  "Identity",
  "RememberName",
  "RecallName"
]), Rc = /* @__PURE__ */ new Set([
  "object-of",
  "verify",
  "locate"
]), kc = /* @__PURE__ */ new Set([
  "subject",
  "object",
  "self"
]), zc = /* @__PURE__ */ new Set([
  "它",
  "这个",
  "那个",
  "这",
  "那"
]), Ic = /* @__PURE__ */ new Set([
  "你",
  "sunland ai",
  "sunland ai · beta"
]);
function Ce(e) {
  return typeof e == "object" && e !== null;
}
function H(e, t) {
  if (typeof e != "string") return null;
  const n = e.trim().replace(/\s+/gu, " ");
  return n.length === 0 || n.length > t ? null : n;
}
function it(e) {
  return zc.has(
    e.trim().replace(/\s+/gu, " ").toLocaleLowerCase("und")
  );
}
function ct(e) {
  return Ic.has(
    e.trim().replace(/\s+/gu, " ").toLocaleLowerCase("und")
  );
}
function Ct(e) {
  if (!Ce(e) || !kc.has(e.kind))
    return null;
  const t = H(
    e.value,
    N.maximumEntityValueLength
  );
  return t === null ? null : Object.freeze({
    kind: e.kind,
    value: t
  });
}
function Nc(e) {
  if (!Ce(e) || !Rc.has(e.kind))
    return;
  const t = H(
    e.relation,
    N.maximumRelationLength
  );
  if (!(t === null || typeof e.hasObject != "boolean"))
    return Object.freeze({
      kind: e.kind,
      relation: t,
      hasObject: e.hasObject
    });
}
function Tc(e) {
  if (!Ce(e) || e.speaker !== "user" && e.speaker !== "assistant")
    return null;
  const t = H(
    e.turnId,
    N.maximumTurnIdLength
  );
  if (t === null) return null;
  const n = typeof e.acceptedIntent == "string" && Cc.has(e.acceptedIntent) ? e.acceptedIntent : void 0, r = Object.freeze(
    (Array.isArray(e.concepts) ? e.concepts : []).map(
      (o) => H(
        o,
        N.maximumEntityValueLength
      )
    ).filter((o) => o !== null).slice(0, N.maximumConceptsPerTurn)
  ), i = Object.freeze(
    (Array.isArray(e.entityReferences) ? e.entityReferences : []).map(Ct).filter(
      (o) => o !== null
    ).slice(0, N.maximumEntitiesPerTurn)
  ), c = Ct(e.focusEntity), s = H(
    e.relation,
    N.maximumRelationLength
  ), a = Nc(e.queryShape);
  return Object.freeze({
    turnId: t,
    speaker: e.speaker,
    ...n === void 0 ? {} : { acceptedIntent: n },
    concepts: r,
    entityReferences: i,
    ...c === null ? {} : { focusEntity: c },
    ...s === null ? {} : { relation: s },
    ...a === void 0 ? {} : { queryShape: a }
  });
}
function Xt() {
  return Object.freeze({
    schemaVersion: 1,
    version: 0,
    recentTurns: Object.freeze([])
  });
}
function X(e) {
  if (!Ce(e)) return Xt();
  const t = typeof e.version == "number" && Number.isSafeInteger(e.version) && e.version >= 0 ? e.version : 0, n = Object.freeze(
    (Array.isArray(e.recentTurns) ? e.recentTurns : []).map(Tc).filter((r) => r !== null).slice(-N.maximumTurns)
  );
  return Object.freeze({
    schemaVersion: 1,
    version: t,
    recentTurns: n
  });
}
function _e(e, t) {
  return Object.freeze({ kind: e, value: t.trim().replace(/\s+/gu, " ") });
}
function Rt(e) {
  return ct(e);
}
function Ac(e) {
  const t = [
    e.selectedCandidate,
    ...e.secondaryCandidates
  ];
  return Object.freeze(
    [...new Set(t.flatMap(({ concepts: n }) => n.map(({ id: r }) => r)))].sort().slice(0, N.maximumConceptsPerTurn)
  );
}
function vc(e, t, n) {
  const r = Ac(n);
  switch (t.type) {
    case "query": {
      const i = _e(
        Rt(t.subject) ? "self" : "subject",
        Rt(t.subject) ? "Sunland AI · Beta" : t.subject
      );
      return Object.freeze({
        turnId: e,
        speaker: "user",
        concepts: r,
        entityReferences: Object.freeze([i]),
        focusEntity: i,
        relation: t.relation,
        queryShape: Object.freeze({
          kind: t.kind,
          relation: t.relation,
          hasObject: t.object !== void 0
        })
      });
    }
    case "statement": {
      const i = _e("subject", t.subject);
      return Object.freeze({
        turnId: e,
        speaker: "user",
        concepts: r,
        entityReferences: Object.freeze([i]),
        focusEntity: i,
        relation: t.relation
      });
    }
    case "intent": {
      if (t.intent === "Identity") {
        const i = _e("self", "Sunland AI · Beta");
        return Object.freeze({
          turnId: e,
          speaker: "user",
          acceptedIntent: t.intent,
          concepts: r,
          entityReferences: Object.freeze([i]),
          focusEntity: i,
          relation: t.entities[1] === "capability" ? "会" : "是"
        });
      }
      return t.intent === "RememberName" ? Object.freeze({
        turnId: e,
        speaker: "user",
        acceptedIntent: t.intent,
        concepts: r,
        entityReferences: Object.freeze([])
      }) : null;
    }
    case "unknown":
      return null;
  }
}
function xc(e) {
  const t = X(e.context);
  if (!e.canCommit || e.decision.kind !== "accept" || e.executedResult === null)
    return Object.freeze({
      kind: "none",
      baseVersion: t.version
    });
  const n = H(
    e.turnId,
    N.maximumTurnIdLength
  );
  if (n === null)
    return Object.freeze({
      kind: "none",
      baseVersion: t.version
    });
  const r = vc(
    n,
    e.executedResult,
    e.decision
  );
  if (r === null)
    return Object.freeze({
      kind: "none",
      baseVersion: t.version
    });
  const i = t.version + 1, c = Object.freeze({
    schemaVersion: 1,
    version: i,
    recentTurns: Object.freeze(
      [...t.recentTurns, r].slice(
        -N.maximumTurns
      )
    )
  });
  return Object.freeze({
    kind: "replace",
    baseVersion: t.version,
    nextVersion: i,
    context: c
  });
}
function ka(e, t) {
  const n = X(e);
  return t.kind !== "replace" || t.baseVersion !== n.version || t.nextVersion !== t.baseVersion + 1 || t.context.version !== t.nextVersion ? n : X(t.context);
}
function Re(e) {
  return e.trim().replace(/\s+/gu, " ").toLocaleLowerCase("und");
}
function $c(e) {
  return [...e.recentTurns].reverse().find(
    (t) => t.relation !== void 0 || t.focusEntity !== void 0 || t.entityReferences.length > 0
  );
}
function Zt(e) {
  const t = $c(e);
  if (t === void 0)
    return Object.freeze({ kind: "none", entities: Object.freeze([]) });
  if (t.focusEntity !== void 0)
    return Object.freeze({
      kind: "unique",
      entities: Object.freeze([t.focusEntity])
    });
  const n = /* @__PURE__ */ new Set(), r = Object.freeze(
    t.entityReferences.filter(({ kind: i }) => i === "subject" || i === "self").filter((i) => {
      const c = Re(i.value);
      return n.has(c) ? !1 : (n.add(c), !0);
    })
  );
  return r.length === 1 ? Object.freeze({ kind: "unique", entities: r }) : r.length > 1 ? Object.freeze({ kind: "ambiguous", entities: r }) : Object.freeze({ kind: "none", entities: r });
}
function Lc(e) {
  var t;
  return ((t = [...e.recentTurns].reverse().find(({ relation: n }) => n !== void 0)) == null ? void 0 : t.relation) ?? null;
}
function ye(e, t, n, r, i) {
  return Object.freeze({
    kind: e,
    value: t,
    rawText: n,
    start: r.start,
    end: r.end,
    source: i,
    confidence: m.context.resolvedQuery
  });
}
function ce(e, t, n, r) {
  return Object.freeze({
    kind: "context-reference",
    key: e,
    value: t,
    weight: n,
    ...r === void 0 ? {} : { rawRange: Object.freeze({ ...r }) }
  });
}
function kt(e, t, n) {
  return Object.freeze({
    id: e,
    canonical: t,
    confidence: m.context.resolvedQuery,
    evidence: n
  });
}
function se(e, t, n, r, i, c) {
  return Object.freeze({
    id: e,
    producer: "context",
    producerWeight: m.producerWeight.context,
    result: t,
    concepts: Object.freeze([...c]),
    entities: Object.freeze([...n]),
    confidence: t === null ? m.context.unresolvedReference : m.context.resolvedQuery,
    evidence: Object.freeze([...r]),
    missingSlots: Object.freeze([...i]),
    sideEffect: "none"
  });
}
function st(e, t) {
  const n = e.input.matchKey.indexOf(t);
  return n < 0 ? Object.freeze({ start: 0, end: 0 }) : D(
    e.input,
    "matchKey",
    n,
    n + t.length
  );
}
function Qe(e) {
  return it(e);
}
function Z(e) {
  return ct(e);
}
function Ke(e, t, n, r, i) {
  const c = st(e, Re(n.subject)), s = e.input.raw.slice(c.start, c.end), a = ye(
    Z(r) ? "self" : "subject",
    Z(r) ? "Sunland AI · Beta" : r,
    s,
    c,
    i
  ), o = Object.freeze({
    ...n,
    subject: a.value
  }), d = ce(
    "context:resolved-subject",
    a.value,
    m.context.inheritedSubject,
    c
  );
  return se(
    `context:query:${o.subject}:${o.relation}:${o.kind}`,
    o,
    Object.freeze([
      a,
      ...t.entities.filter(({ kind: l }) => l !== "subject")
    ]),
    Object.freeze([...t.evidence, d]),
    Object.freeze([]),
    t.concepts
  );
}
function _c(e, t, n, r) {
  const i = st(e, Re(n.subject)), c = Object.freeze([
    ...t.evidence,
    ce(
      r.kind === "ambiguous" ? "context:ambiguous-subject" : "context:missing-subject",
      n.subject,
      m.context.unresolvedReference,
      i
    )
  ]), s = r.entities.map(
    (a) => ye(
      a.kind === "self" ? "self" : "subject",
      a.value,
      "",
      Object.freeze({ start: 0, end: 0 }),
      "context"
    )
  );
  return se(
    `context:partial:${n.relation}:${r.kind}`,
    null,
    Object.freeze(s),
    c,
    Object.freeze(["subject"]),
    t.concepts
  );
}
function Kc(e, t, n) {
  const r = Zt(n), i = [], c = [], s = t.some(
    ({ result: a }) => (a == null ? void 0 : a.type) === "query" && a.kind === "object-of" && a.relation === "意思是"
  );
  for (const a of t) {
    const o = a.result;
    if (s && a.producer === "legacy-regex" && (o == null ? void 0 : o.type) === "intent" && o.intent === "Identity") {
      c.push(a.id);
      continue;
    }
    if ((o == null ? void 0 : o.type) === "statement" && Qe(o.subject)) {
      const d = st(
        e,
        Re(o.subject)
      ), l = ce(
        "context:side-effect-subject-prohibited",
        o.subject,
        m.context.unresolvedReference,
        d
      );
      i.push(
        se(
          `context:partial:side-effect-subject:${o.relation}`,
          null,
          Object.freeze([]),
          Object.freeze([...a.evidence, l]),
          Object.freeze(["subject"]),
          a.concepts
        )
      ), c.push(a.id);
      continue;
    }
    if ((o == null ? void 0 : o.type) === "query") {
      if (o.kind === "object-of" && o.relation === "意思是") {
        i.push(
          Ke(
            e,
            a,
            o,
            o.subject,
            "explicit"
          )
        ), c.push(a.id);
        continue;
      }
      if (Z(o.subject)) {
        i.push(
          Ke(
            e,
            a,
            o,
            "Sunland AI · Beta",
            "explicit"
          )
        ), c.push(a.id);
        continue;
      }
      Qe(o.subject) && (c.push(a.id), r.kind === "unique" ? i.push(
        Ke(
          e,
          a,
          o,
          r.entities[0].value,
          "context"
        )
      ) : i.push(
        _c(
          e,
          a,
          o,
          r
        )
      ));
    }
  }
  return Object.freeze({
    candidates: Object.freeze(i),
    supersededCandidateIds: Object.freeze(c)
  });
}
function Mc(e, t) {
  var a;
  const n = e.input.surface.toLocaleLowerCase("und"), r = /^(?:那\s*)?(.+?)\s*呢$/u.exec(
    n
  );
  if (r === null) return null;
  const i = ((a = r[1]) == null ? void 0 : a.trim()) ?? "";
  if (i.length === 0) return null;
  const c = n.indexOf(i), s = D(
    e.input,
    "surface",
    c,
    c + i.length
  );
  if (Z(i))
    return Object.freeze({
      value: "Sunland AI · Beta",
      rawRange: s,
      source: "explicit",
      ambiguousEntities: Object.freeze([])
    });
  if (Qe(i)) {
    const o = Zt(t);
    return o.kind !== "unique" ? Object.freeze({
      value: "",
      rawRange: s,
      source: "context",
      ambiguousEntities: o.entities
    }) : Object.freeze({
      value: o.entities[0].value,
      rawRange: s,
      source: "context",
      ambiguousEntities: Object.freeze([])
    });
  }
  return Object.freeze({
    value: e.input.raw.slice(s.start, s.end).trim().replace(/\s+/gu, " "),
    rawRange: s,
    source: "explicit",
    ambiguousEntities: Object.freeze([])
  });
}
function Pc(e, t) {
  const n = Mc(e, t);
  if (n === null) return null;
  const r = Lc(t), i = ce(
    n.value.length === 0 ? "context:ambiguous-subject" : "context:ellipsis-subject",
    n.value,
    m.context.inheritedSubject,
    n.rawRange
  );
  if (n.value.length === 0 || r === null) {
    const l = Object.freeze([
      ...n.value.length === 0 ? ["subject"] : [],
      ...r === null ? ["relation"] : []
    ]), b = n.ambiguousEntities.map(
      (g) => ye(
        g.kind === "self" ? "self" : "subject",
        g.value,
        "",
        Object.freeze({ start: 0, end: 0 }),
        "context"
      )
    );
    return se(
      `context:ellipsis:partial:${l.join("+")}`,
      null,
      Object.freeze(b),
      Object.freeze([i]),
      l,
      Object.freeze([
        kt(
          "context-ellipsis",
          "context ellipsis",
          Object.freeze([i])
        )
      ])
    );
  }
  const c = ye(
    Z(n.value) ? "self" : "subject",
    Z(n.value) ? "Sunland AI · Beta" : n.value,
    e.input.raw.slice(
      n.rawRange.start,
      n.rawRange.end
    ),
    n.rawRange,
    n.source
  ), s = ce(
    "context:inherited-relation",
    r,
    m.context.inheritedRelation
  ), a = r === "在" ? "locate" : "object-of", o = Object.freeze({
    type: "query",
    subject: c.value,
    relation: r,
    kind: a,
    raw: e.input.raw
  }), d = Object.freeze([i, s]);
  return se(
    `context:ellipsis:query:${c.value}:${r}`,
    o,
    Object.freeze([c]),
    d,
    Object.freeze([]),
    Object.freeze([
      kt("context-ellipsis", "context ellipsis", d)
    ])
  );
}
function Dc(e, t, n) {
  var s;
  const r = Kc(
    e,
    t,
    n
  ), i = Pc(e, n), c = ((s = i == null ? void 0 : i.result) == null ? void 0 : s.type) === "query" ? t.filter(
    ({ producer: a, result: o }) => a === "legacy-regex" && (o == null ? void 0 : o.type) === "intent" && o.intent === "Identity"
  ).map(({ id: a }) => a) : [];
  return Object.freeze({
    candidates: Object.freeze([
      ...r.candidates,
      ...i === null ? [] : [i]
    ]),
    supersededCandidateIds: Object.freeze([
      ...r.supersededCandidateIds,
      ...c
    ])
  });
}
const Uc = Object.freeze({
  Greeting: Object.freeze(["greeting"]),
  Thanks: Object.freeze(["thanks"]),
  Farewell: Object.freeze(["goodbye"]),
  Identity: Object.freeze(["identity-name", "identity-self"]),
  RememberName: Object.freeze(["remember-name"]),
  RecallName: Object.freeze(["recall-name"])
});
function qc(e) {
  switch (e.type) {
    case "intent":
      return `intent:${e.intent}:${e.entities.join("|")}`;
    case "statement":
      return `statement:${e.subject}:${e.relation}:${e.object}:${e.negated}`;
    case "query":
      return `query:${e.kind}:${e.subject}:${e.relation}:${e.object ?? ""}`;
    case "unknown":
      return "unknown";
  }
}
function Bc(e, t) {
  if (e.type === "intent") {
    const n = Uc[e.intent] ?? [];
    return Object.freeze(
      t.concepts.filter((r) => n.includes(r.id))
    );
  }
  return e.type === "statement" || e.type === "query" ? Object.freeze(
    t.concepts.filter(
      (n) => t.relations.some(
        (r) => r.conceptId === n.id && r.canonical === e.relation
      )
    )
  ) : Object.freeze([]);
}
function Fc(e) {
  switch (e.type) {
    case "intent":
      return T(
        Math.max(
          m.legacy.intentFloor,
          je(e.confidence)
        )
      );
    case "statement":
      return m.legacy.statement;
    case "query":
      return m.legacy.query;
    case "unknown":
      return m.legacy.unknown;
  }
}
function Wc(e) {
  const t = Mt().parse(e.input.raw), n = Fc(t), r = Object.freeze({
    start: 0,
    end: e.input.raw.length
  }), i = Object.freeze([
    Object.freeze({
      kind: "legacy-regex",
      key: `legacy:${t.type}`,
      value: t.type,
      rawRange: r,
      weight: n
    })
  ]);
  return Object.freeze({
    id: `legacy-regex:${qc(t)}`,
    producer: "legacy-regex",
    producerWeight: m.producerWeight["legacy-regex"],
    result: t,
    concepts: Bc(t, e),
    entities: e.entities,
    confidence: n,
    evidence: i,
    missingSlots: t.type === "unknown" ? Object.freeze(["interpretation"]) : Object.freeze([]),
    sideEffect: t.type === "statement" ? "knowledge-write" : "none"
  });
}
const Vc = Object.freeze({
  greeting: Object.freeze({ intent: "Greeting", sideEffect: "none" }),
  thanks: Object.freeze({ intent: "Thanks", sideEffect: "none" }),
  goodbye: Object.freeze({ intent: "Farewell", sideEffect: "none" }),
  "identity-name": Object.freeze({
    intent: "Identity",
    sideEffect: "none"
  }),
  "identity-self": Object.freeze({
    intent: "Identity",
    sideEffect: "none"
  }),
  "remember-name": Object.freeze({
    intent: "RememberName",
    sideEffect: "memory-write"
  }),
  "recall-name": Object.freeze({
    intent: "RecallName",
    sideEffect: "none"
  })
});
function en(e) {
  return e.evidence[0] ?? null;
}
function Gc(e, t) {
  var r, i;
  const n = ((i = (r = en(e)) == null ? void 0 : r.rawRange) == null ? void 0 : i.end) ?? 0;
  return [...t.personNames].filter((c) => c.start >= n).sort(
    (c, s) => c.start - s.start || c.end - s.end
  )[0] ?? null;
}
function Yc(e, t, n) {
  var i, c;
  const r = ((c = (i = en(e)) == null ? void 0 : i.rawRange) == null ? void 0 : c.start) ?? 0;
  return n.negationCues.some((s) => {
    const a = s.rawRange;
    return a !== void 0 && a.start >= r && a.end <= t.end;
  });
}
function Qc(e) {
  var n;
  const t = ((n = e.selfReferences[0]) == null ? void 0 : n.value) ?? "Sunland AI · Beta";
  return Object.freeze([t, "identity"]);
}
function Hc(e, t, n, r) {
  return Object.freeze({
    type: "intent",
    intent: e,
    entities: Object.freeze([...t]),
    confidence: n,
    raw: r
  });
}
function Jc(e, t) {
  const n = Vc[e.id];
  if (n === void 0)
    return null;
  let r = Object.freeze([]), i = Object.freeze([]);
  if (n.intent === "Identity" && (r = t.selfReferences, i = Qc(t)), n.intent === "RememberName") {
    const l = Gc(e, t);
    if (l === null || Yc(e, l, t))
      return null;
    r = Object.freeze([l]), i = Object.freeze([l.value]);
  }
  const c = r.length > 0 ? [m.lexicon.entityCompleteBonus] : [], s = n.sideEffect === "none" ? [] : [m.lexicon.sideEffectPenalty], a = we(
    e.confidence,
    c,
    s
  ), o = Hc(
    n.intent,
    i,
    a,
    t.input.raw
  ), d = Object.freeze([
    ...e.evidence,
    ...r.map(
      (l) => Object.freeze({
        kind: "entity-pattern",
        key: `entity:${l.kind}`,
        value: l.value,
        rawRange: Object.freeze({
          start: l.start,
          end: l.end
        }),
        weight: l.confidence
      })
    )
  ]);
  return Object.freeze({
    id: `lexicon:intent:${n.intent}:${i.join("|")}`,
    producer: "lexicon",
    producerWeight: m.producerWeight.lexicon,
    result: o,
    concepts: Object.freeze([e]),
    entities: r,
    confidence: a,
    evidence: d,
    missingSlots: Object.freeze([]),
    sideEffect: n.sideEffect
  });
}
function Xc(e) {
  const t = e.concepts.some(
    ({ id: n }) => n === "recall-name"
  );
  return Object.freeze(
    e.concepts.filter(
      ({ id: n }) => !(t && n === "remember-name")
    ).map((n) => Jc(n, e)).filter(
      (n) => n !== null
    )
  );
}
const tn = /[,;!?]/u, zt = /[\s,.;:!?'"()[\]~]/u, nn = /* @__PURE__ */ new Set(["什么", "啥", "谁", "哪", "哪里"]), rn = /[吗呢]$/u, Zc = /(?:不是|不会|不能|没有|不|没)$/u;
function es(e, t) {
  let n = 0;
  for (let c = t - 1; c >= 0; c -= 1)
    if (tn.test(e[c])) {
      n = c + 1;
      break;
    }
  const r = e.slice(n, t), i = r.lastIndexOf("和");
  return i >= 0 && /(?:什么|啥|谁|吗|呢|\?)/u.test(r.slice(0, i)) ? n + i + 1 : n;
}
function ts(e, t) {
  for (let n = t; n < e.length; n += 1)
    if (tn.test(e[n]))
      return n;
  return e.length;
}
function Oe(e, t, n) {
  let r = t, i = n;
  for (; r < i && zt.test(e[r]); )
    r += 1;
  for (; i > r && zt.test(e[i - 1]); )
    i -= 1;
  return r >= i ? null : Object.freeze({
    start: r,
    end: i,
    value: e.slice(r, i)
  });
}
function ns(e, t) {
  if (t === null)
    return Object.freeze({ segment: null, negated: !1 });
  const n = Zc.exec(t.value);
  return Object.freeze(n === null ? { segment: t, negated: !1 } : {
    segment: Oe(
      e,
      t.start,
      t.end - n[0].length
    ),
    negated: !0
  });
}
function rs(e, t) {
  if (t === null)
    return null;
  const n = rn.exec(t.value);
  return n === null ? t : Oe(
    e,
    t.start,
    t.end - n[0].length
  );
}
function cn(e, t) {
  return D(
    e.input,
    "matchKey",
    t.start,
    t.end
  );
}
function is(e, t) {
  const n = cn(e, t);
  return e.input.raw.slice(n.start, n.end).trim().replace(/\s+/gu, " ").replace(/^["“”'‘’]+|["“”'‘’]+$/gu, "");
}
function It(e, t, n, r) {
  const i = cn(e, n);
  return Object.freeze({
    kind: t,
    value: is(e, n),
    rawText: e.input.raw.slice(i.start, i.end),
    start: i.start,
    end: i.end,
    source: "explicit",
    confidence: r
  });
}
function cs(e, t) {
  return e.concepts.find(
    (n) => n.id === t.conceptId && n.evidence.some(
      (r) => {
        var i;
        return ((i = r.rawRange) == null ? void 0 : i.start) === t.entity.start && r.rawRange.end === t.entity.end;
      }
    )
  ) ?? Object.freeze({
    id: t.conceptId,
    canonical: t.canonical,
    matchedAlias: t.alias,
    confidence: t.confidence,
    evidence: t.evidence
  });
}
function ss(e, t) {
  return e.concepts.filter(
    (n) => n.id === "remember-name" || n.id === "recall-name"
  ).some(
    (n) => n.evidence.some((r) => {
      const i = r.rawRange;
      return i !== void 0 && t.entity.start >= i.start && t.entity.end <= i.end;
    })
  );
}
function as(e, t, n, r) {
  if (r !== null && nn.has(r.value.replace(rn, "")))
    return !0;
  const i = t < n ? D(
    e.input,
    "matchKey",
    t,
    n
  ) : null;
  return e.questionCues.some((c) => {
    const s = c.rawRange;
    return s !== void 0 && i !== null && s.start >= i.start && s.end <= i.end;
  });
}
function os(e, t, n, r, i, c) {
  return n === null ? null : i === "object-of" ? Object.freeze({
    type: "query",
    subject: n.value,
    relation: t.canonical,
    kind: "object-of",
    raw: e.input.raw
  }) : i === "verify" ? r === null ? null : Object.freeze({
    type: "query",
    subject: n.value,
    relation: t.canonical,
    object: r.value,
    kind: "verify",
    raw: e.input.raw
  }) : r === null ? null : Object.freeze({
    type: "statement",
    subject: n.value,
    relation: t.canonical,
    object: r.value,
    negated: c,
    raw: e.input.raw
  });
}
function us(e, t) {
  if (ss(e, t))
    return null;
  const n = e.input.matchKey, r = es(n, t.matchKeyRange.start), i = ts(n, t.matchKeyRange.end), c = Oe(
    n,
    r,
    t.matchKeyRange.start
  ), s = ns(n, c), a = Oe(
    n,
    t.matchKeyRange.end,
    i
  ), o = rs(n, a), d = as(
    e,
    r,
    i,
    o
  ), l = t.alias === "是什么意思" || o !== null && nn.has(o.value), b = l ? "object-of" : d ? "verify" : null, g = l ? null : o, S = s.segment === null ? null : It(
    e,
    "subject",
    s.segment,
    t.confidence
  ), R = g === null ? null : It(
    e,
    "object",
    g,
    t.confidence
  ), w = os(
    e,
    t,
    S,
    R,
    b,
    s.negated
  ), B = [];
  S === null && B.push("subject"), (b === null || b === "verify") && R === null && B.push("object");
  const oe = (w == null ? void 0 : w.type) === "statement" ? "knowledge-write" : "none", A = [
    t.confidence * m.relation.conceptWeightShare,
    ...S === null ? [] : [m.relation.subjectBonus],
    ...R === null ? [] : [m.relation.objectBonus],
    b !== null ? m.relation.queryShapeBonus : m.relation.statementShapeBonus
  ], ke = [
    ...B.map(
      () => m.relation.missingSlotPenalty
    ),
    ...oe === "none" ? [] : [m.relation.sideEffectPenalty],
    ...t.alias.length === 1 ? [m.relation.weakSingleCharacterPenalty] : []
  ], ze = we(
    m.relation.base,
    A,
    ke
  ), ue = Object.freeze(
    [S, t.entity, R].filter(
      (k) => k !== null
    )
  ), v = Object.freeze([
    ...t.evidence,
    ...ue.filter((k) => k.kind !== "relation").map(
      (k) => Object.freeze({
        kind: "relation-pattern",
        key: `slot:${k.kind}`,
        value: k.value,
        rawRange: Object.freeze({
          start: k.start,
          end: k.end
        }),
        weight: k.confidence
      })
    ),
    ...b !== null ? e.questionCues : e.teachingCues,
    ...s.negated ? e.negationCues : []
  ]), Ie = w === null ? `partial:${t.canonical}:${t.entity.start}` : w.type === "query" ? `query:${w.subject}:${w.relation}` : `statement:${w.subject}:${w.relation}:${w.object}:${w.negated}`;
  return Object.freeze({
    id: `relation-pattern:${Ie}`,
    producer: "relation-pattern",
    producerWeight: m.producerWeight["relation-pattern"],
    result: w,
    concepts: Object.freeze([cs(e, t)]),
    entities: ue,
    confidence: ze,
    evidence: v,
    missingSlots: Object.freeze(B),
    sideEffect: oe
  });
}
function ls(e) {
  var s;
  const t = e.teachingCues.filter(
    ({ key: a }) => a === "teaching:explicit"
  );
  if (t.length === 0 || e.relations.length > 0)
    return null;
  const n = e.concepts.filter(
    ({ id: a }) => a === "teaching"
  ), r = Object.freeze([
    "subject",
    "relation",
    "object"
  ]), i = we(
    m.relation.base,
    [],
    r.map(
      () => m.relation.missingSlotPenalty
    )
  ), c = (s = t[0]) == null ? void 0 : s.rawRange;
  return Object.freeze({
    id: `relation-pattern:partial-teaching:${(c == null ? void 0 : c.start) ?? 0}`,
    producer: "relation-pattern",
    producerWeight: m.producerWeight["relation-pattern"],
    result: null,
    concepts: Object.freeze(n),
    entities: Object.freeze([]),
    confidence: i,
    evidence: Object.freeze(t),
    missingSlots: r,
    sideEffect: "none"
  });
}
function fs(e) {
  const t = ls(e);
  return Object.freeze(
    [
      ...e.relations.map(
        (n) => us(e, n)
      ),
      t
    ].filter(
      (n) => n !== null
    )
  );
}
function ds(e) {
  if (e === null)
    return "partial";
  switch (e.type) {
    case "intent":
      return `intent:${e.intent}:${e.entities.join("|")}`;
    case "statement":
      return `statement:${e.subject}:${e.relation}:${e.object}:${e.negated}`;
    case "query":
      return `query:${e.kind}:${e.subject}:${e.relation}:${e.object ?? ""}`;
    case "unknown":
      return "unknown";
  }
}
function ms(e) {
  const t = e.result === null ? e.id : ds(e.result);
  return [
    e.producer,
    t,
    [...e.missingSlots].sort().join(",")
  ].join("::");
}
function bs(e) {
  var t, n;
  return [
    e.kind,
    e.key,
    e.value ?? "",
    ((t = e.rawRange) == null ? void 0 : t.start) ?? "",
    ((n = e.rawRange) == null ? void 0 : n.end) ?? ""
  ].join(":");
}
function gs(e) {
  var n, r;
  const t = e.evidence[0];
  return [
    e.id,
    ((n = t == null ? void 0 : t.rawRange) == null ? void 0 : n.start) ?? "",
    ((r = t == null ? void 0 : t.rawRange) == null ? void 0 : r.end) ?? ""
  ].join(":");
}
function hs(e) {
  return [
    e.kind,
    e.start,
    e.end,
    e.value
  ].join(":");
}
function Me(e, t) {
  const n = /* @__PURE__ */ new Set(), r = [];
  for (const i of e) {
    const c = t(i);
    n.has(c) || (n.add(c), r.push(i));
  }
  return Object.freeze(r);
}
function ps(e, t) {
  const n = {
    none: 0,
    "memory-write": 1,
    "knowledge-write": 2
  };
  return n[e] >= n[t] ? e : t;
}
function js(e, t) {
  return Object.freeze({
    id: e.id.localeCompare(t.id) <= 0 ? e.id : t.id,
    producer: e.producer,
    producerWeight: je(
      Math.max(e.producerWeight, t.producerWeight)
    ),
    result: e.result ?? t.result,
    concepts: Me(
      [...e.concepts, ...t.concepts],
      gs
    ),
    entities: Me(
      [...e.entities, ...t.entities],
      hs
    ),
    confidence: je(
      Math.max(e.confidence, t.confidence)
    ),
    evidence: Me(
      [...e.evidence, ...t.evidence],
      bs
    ),
    missingSlots: Object.freeze(
      [.../* @__PURE__ */ new Set([...e.missingSlots, ...t.missingSlots])].sort()
    ),
    sideEffect: ps(
      e.sideEffect,
      t.sideEffect
    )
  });
}
function ys(e) {
  const t = /* @__PURE__ */ new Map();
  for (const n of e) {
    const r = ms(n), i = t.get(r);
    t.set(
      r,
      i === void 0 ? n : js(i, n)
    );
  }
  return Object.freeze([...t.values()]);
}
function Os(e) {
  return Object.freeze(
    [...e].sort(
      (t, n) => n.confidence - t.confidence || t.missingSlots.length - n.missingSlots.length || m.producerTieBreak[t.producer] - m.producerTieBreak[n.producer] || t.id.localeCompare(n.id)
    )
  );
}
function Ss(e, t, n) {
  const r = [];
  return e.trim().length === 0 && r.push(
    Object.freeze({
      level: "info",
      code: "semantic.empty-input",
      message: "Input contains no semantic surface content."
    })
  ), t.every(
    (i) => {
      var c;
      return i.producer === "legacy-regex" && ((c = i.result) == null ? void 0 : c.type) === "unknown";
    }
  ) && r.push(
    Object.freeze({
      level: "debug",
      code: "semantic.no-structured-candidate",
      message: "No structured semantic candidate was generated."
    })
  ), n !== void 0 && t.some(({ producer: i }) => i === "context") && r.push(
    Object.freeze({
      level: "debug",
      code: "semantic.context-candidate-generated",
      message: "A bounded context candidate was generated."
    })
  ), Object.freeze(r);
}
function Es(e, t) {
  const n = lc(e), r = wc(n), i = [
    Wc(r),
    ...Xc(r),
    ...fs(r)
  ], c = t === void 0 ? void 0 : X(t), s = c === void 0 ? Object.freeze({
    candidates: Object.freeze([]),
    supersededCandidateIds: Object.freeze([])
  }) : Dc(
    r,
    i,
    c
  ), a = new Set(s.supersededCandidateIds), o = [
    ...i.filter(({ id: l }) => !a.has(l)),
    ...s.candidates
  ], d = Os(
    ys(o)
  );
  return Object.freeze({
    input: n,
    extraction: r,
    candidates: d,
    diagnostics: Ss(
      e,
      d,
      c
    )
  });
}
const ws = /^(?:你好|您好|嗨|哈喽|hello|hi)[,，]\s*/iu;
function sn(e) {
  return e.type === "intent" && e.intent === "RememberName";
}
function an(e) {
  return e.type === "statement" || sn(e);
}
function on(e) {
  var t, n;
  return e.sideEffect !== "none" || ((t = e.result) == null ? void 0 : t.type) === "statement" || ((n = e.result) == null ? void 0 : n.type) === "intent" && e.result.intent === "RememberName";
}
function pe(e) {
  return e.trim().replace(/\s+/gu, " ").toLocaleLowerCase("und");
}
function Cs(e, t) {
  let n = pe(e.relation), r = pe(e.object);
  const i = t.extraction.relations.some(
    ({ conceptId: c }) => c === "is-a"
  );
  return n === "是" && i && (n = "属于"), n === "属于" && r.startsWith("一种") && r.length > 2 && (r = r.slice(2)), n === "指的是" && (n = "意思是"), Object.freeze([
    pe(e.subject),
    n,
    r,
    e.negated
  ]);
}
function He(e, t) {
  if ((e == null ? void 0 : e.type) === "statement")
    return `knowledge:${Cs(e, t).join("|")}`;
  if ((e == null ? void 0 : e.type) === "intent" && e.intent === "RememberName") {
    const n = e.entities[0];
    return n === void 0 ? null : `memory:name:${pe(n)}`;
  }
  return null;
}
function Rs(e) {
  return e.kind === "accept" ? Object.freeze([
    e.selectedCandidate,
    ...e.secondaryCandidates
  ]) : Object.freeze([]);
}
function ks(e) {
  return new Set(
    e.candidates.filter(on).filter(
      (t) => t.result !== null && t.result.type !== "unknown" && t.missingSlots.length === 0
    ).map(
      (t) => He(t.result, e)
    ).filter((t) => t !== null)
  );
}
function zs(e) {
  return sn(e) ? e.raw.trim().replace(ws, "") : e.raw;
}
function K(e) {
  return Object.freeze({
    kind: "block-and-no-understanding",
    reason: e
  });
}
function Is(e, t, n) {
  if (!an(t))
    return Object.freeze({
      kind: "allow-passive-legacy",
      reason: "not-a-side-effect"
    });
  if (e.kind === "clarify")
    return Object.freeze({
      kind: "block-and-clarify",
      reason: "semantic-clarification-required",
      decision: e
    });
  if (e.kind === "reject-side-effect")
    return K("semantic-side-effect-rejected");
  if (e.kind !== "accept")
    return K("semantic-side-effect-not-accepted");
  if (n.extraction.negationCues.length > 0)
    return K("negation-detected");
  if (n.extraction.questionCues.length > 0)
    return K("question-detected");
  if (_t(n.input.raw))
    return K("explicit-prohibition");
  if (et(
    zs(t)
  ))
    return K("unsafe-input-structure");
  const r = Rs(
    e
  ).filter(on);
  if (r.length === 0 || r.some(
    (s) => s.result === null || s.missingSlots.length > 0
  ))
    return K(
      r.length === 0 ? "semantic-side-effect-not-accepted" : "missing-required-slot"
    );
  if (ks(n).size > 1)
    return K("compound-or-conflicting-side-effect");
  const i = He(
    t,
    n
  ), c = new Set(
    r.map(
      (s) => He(s.result, n)
    ).filter((s) => s !== null)
  );
  return i === null || !c.has(i) ? Object.freeze({
    kind: "reject",
    reason: "side-effect-interpretation-mismatch"
  }) : Object.freeze({
    kind: "allow-legacy-side-effect",
    reason: "semantic-side-effect-confirmed"
  });
}
const Ns = /* @__PURE__ */ new Set([
  "Greeting",
  "Thanks",
  "Farewell",
  "Identity",
  "RecallName"
]), Ts = /* @__PURE__ */ new Set([
  "subject",
  "relation",
  "object",
  "name",
  "intent"
]);
function E(e) {
  return e.trim().replace(/\s+/gu, " ").toLocaleLowerCase("und");
}
function un(e) {
  var t, n;
  return e.sideEffect !== "none" || ((t = e.result) == null ? void 0 : t.type) === "statement" || ((n = e.result) == null ? void 0 : n.type) === "intent" && e.result.intent === "RememberName";
}
function As(e) {
  return e.type === "query" || e.type === "intent" && Ns.has(e.intent);
}
function ln(e, t) {
  if (e.type !== t.type) return !1;
  switch (e.type) {
    case "intent":
      return t.type !== "intent" ? !1 : e.intent === t.intent && e.entities.length === t.entities.length && e.entities.every(
        (n, r) => E(n) === E(t.entities[r] ?? "")
      );
    case "query":
      return t.type === "query" && e.kind === t.kind && E(e.subject) === E(t.subject) && E(e.relation) === E(t.relation) && E(e.object ?? "") === E(t.object ?? "") && e.explain === t.explain;
    case "statement":
      return t.type === "statement" && E(e.subject) === E(t.subject) && E(e.relation) === E(t.relation) && E(e.object) === E(t.object) && e.negated === t.negated;
    case "unknown":
      return t.type === "unknown";
  }
}
function vs(e, t) {
  const n = e.result;
  return e.producer !== "context" || (n == null ? void 0 : n.type) !== "query" ? !1 : t.type === "intent" && t.intent === "Identity" ? n.relation === "意思是" || e.concepts.some(({ id: r }) => r === "context-ellipsis") : t.type !== "query" || !it(t.subject) && !ct(t.subject) ? !1 : E(n.relation) === E(t.relation) && n.kind === t.kind && E(n.object ?? "") === E(t.object ?? "");
}
function xs(e) {
  const t = e.result;
  if ((t == null ? void 0 : t.type) === "intent")
    switch (t.intent) {
      case "Greeting":
        return "greeting";
      case "Thanks":
        return "thanks";
      case "Farewell":
        return "farewell";
      case "Identity":
        return "identity";
      case "RecallName":
        return "recall-name";
      case "RememberName":
        return "remember-name";
    }
  return (t == null ? void 0 : t.type) === "query" ? "query" : (t == null ? void 0 : t.type) === "statement" || e.concepts.some(({ id: n }) => n === "teaching") ? "teaching" : "unknown";
}
function $s(e) {
  var n;
  const t = e == null ? void 0 : e.result;
  return (t == null ? void 0 : t.type) === "query" || (t == null ? void 0 : t.type) === "statement" ? t.relation : (n = e == null ? void 0 : e.entities.find(({ kind: r }) => r === "relation")) == null ? void 0 : n.value;
}
function Ls(e) {
  return e.clarificationKind === "ambiguous-intent" || e.clarificationKind === "conflicting-candidates" ? "ambiguous" : e.clarificationKind === "uncertain-name" || e.clarificationKind === "uncertain-teaching" ? "uncertain" : "missing-information";
}
function fn(e) {
  const t = Object.freeze(
    [...new Set(e.missingSlots)].filter(
      (c) => Ts.has(c)
    ).sort()
  ), n = Object.freeze(
    [...new Set(e.candidateOptions.map(xs))].sort()
  ), r = Object.freeze(
    [
      ...new Set(
        e.candidateOptions.flatMap(
          ({ entities: c }) => c.filter(
            ({ source: s, kind: a }) => s === "context" && (a === "subject" || a === "self")
          ).map(({ value: s }) => s)
        )
      )
    ].filter((c) => c.length > 0 && c.length <= 80).slice(0, 3)
  ), i = $s(e.candidateOptions[0]);
  return Object.freeze({
    clarificationKind: e.clarificationKind,
    missingSlots: t,
    candidateLabels: n,
    reasonCategory: Ls(e),
    ...i === void 0 ? {} : { relation: i },
    ...r.length === 0 ? {} : { contextLabels: r }
  });
}
function _s(e, t) {
  return t.type === "unknown" || t.type === "query" && it(t.subject) && e.missingSlots.includes("subject") && e.candidateOptions.some(
    ({ producer: n }) => n === "context"
  ) || e.reasonCodes.includes("compound-query") && e.candidateOptions.length >= 2 && e.candidateOptions.every(
    (n) => !un(n)
  ) ? !0 : t.type === "statement" && e.missingSlots.includes("object") && /^(?:吗|呢|什么|啥|\?)$/u.test(t.object.trim()) && e.candidateOptions.some(
    (n) => n.evidence.some(({ kind: r }) => r === "question-cue")
  );
}
function Je(e, t) {
  return Object.freeze({
    kind: "no-understanding",
    failure: Object.freeze({
      type: "unknown",
      raw: e.raw,
      reason: t
    })
  });
}
function Ks(e, t) {
  switch (e.kind) {
    case "allow-passive-legacy":
      return null;
    case "allow-legacy-side-effect":
      return Object.freeze({
        kind: "fallback-legacy",
        result: t,
        reason: "side-effect-prohibited"
      });
    case "block-and-clarify":
      return Object.freeze({
        kind: "clarification",
        context: fn(e.decision)
      });
    case "block-and-no-understanding":
      return Je(
        t,
        `legacy-side-effect-blocked:${e.reason}`
      );
    case "reject":
      return Je(
        t,
        `legacy-side-effect-rejected:${e.reason}`
      );
  }
}
function Ms(e, t, n) {
  const r = Ks(
    Is(
      e,
      t,
      n
    ),
    t
  );
  if (r !== null) return r;
  switch (e.kind) {
    case "accept": {
      if ([
        e.selectedCandidate,
        ...e.secondaryCandidates
      ].some(un))
        return Object.freeze({
          kind: "fallback-legacy",
          result: t,
          reason: "side-effect-prohibited"
        });
      const c = e.selectedCandidate.result;
      return c === null || c.type === "unknown" ? Object.freeze({
        kind: "fallback-legacy",
        result: t,
        reason: "incomplete-result"
      }) : e.selectedCandidate.missingSlots.length > 0 || !As(c) ? Object.freeze({
        kind: "fallback-legacy",
        result: t,
        reason: "unsupported-result"
      }) : t.type !== "unknown" && !ln(c, t) && !vs(
        e.selectedCandidate,
        t
      ) ? Object.freeze({
        kind: "fallback-legacy",
        result: t,
        reason: "legacy-conflict"
      }) : Object.freeze({ kind: "adopt", result: c });
    }
    case "clarify":
      return _s(e, t) ? Object.freeze({
        kind: "clarification",
        context: fn(e)
      }) : Object.freeze({
        kind: "fallback-legacy",
        result: t,
        reason: "legacy-conflict"
      });
    case "reject-side-effect":
      return t.type === "unknown" ? Je(
        t,
        "semantic-side-effect-rejected"
      ) : Object.freeze({
        kind: "fallback-legacy",
        result: t,
        reason: "side-effect-rejected"
      });
    case "no-understanding":
      return t.type === "unknown" ? Object.freeze({
        kind: "no-understanding",
        failure: t
      }) : Object.freeze({
        kind: "fallback-legacy",
        result: t,
        reason: "legacy-conflict"
      });
  }
}
function Ps(e) {
  switch (e.kind) {
    case "accept":
      return e.selectedCandidate;
    case "clarify":
      return e.candidateOptions[0];
    case "reject-side-effect":
      return e.rejectedCandidate;
    case "no-understanding":
      return;
  }
}
function Ds(e) {
  var t;
  return e === void 0 ? null : ((t = e.result) == null ? void 0 : t.type) ?? "partial";
}
function Us(e) {
  if (e === void 0) return null;
  const t = e.result;
  return (t == null ? void 0 : t.type) === "intent" ? `semantic:${e.producer}:intent:${t.intent}` : `semantic:${e.producer}:${(t == null ? void 0 : t.type) ?? "partial"}`;
}
function qs(e) {
  return Object.freeze([...e.reasonCodes]);
}
function Bs(e, t) {
  return e.kind === "accept" ? e.confidence : (t == null ? void 0 : t.confidence) ?? null;
}
function Fs(e, t, n, r) {
  const i = Ps(n), c = (i == null ? void 0 : i.result) === void 0 || i.result === null ? !1 : ln(i.result, t), s = e === "passive" && r.kind !== "fallback-legacy";
  return Object.freeze({
    mode: e,
    legacyType: t.type,
    decisionType: n.kind,
    selectedCandidateId: Us(i),
    selectedCandidateType: Ds(i),
    confidence: Bs(n, i),
    reasonCodes: qs(n),
    equivalentToLegacy: c,
    semanticAdopted: s,
    fellBackToLegacy: e === "shadow" || r.kind === "fallback-legacy",
    adapterKind: r.kind,
    semanticError: !1
  });
}
function Ws(e, t) {
  return Object.freeze({
    mode: e,
    legacyType: t.type,
    decisionType: "error",
    selectedCandidateId: null,
    selectedCandidateType: null,
    confidence: null,
    reasonCodes: Object.freeze([]),
    equivalentToLegacy: !1,
    semanticAdopted: !1,
    fellBackToLegacy: !0,
    adapterKind: "error",
    semanticError: !0
  });
}
const Vs = Object.freeze({
  passiveIntentAcceptThreshold: T(0.72),
  queryAcceptThreshold: T(0.74),
  sideEffectAcceptThreshold: T(0.82),
  minimumCandidateMargin: T(0.08),
  partialCandidateThreshold: T(0.35),
  maximumAlternatives: 3,
  minimumSideEffectEvidenceUnits: 2,
  weakAliasMaximumLength: 1,
  missingSlotPolicy: Object.freeze({
    partialDecision: "clarify",
    sideEffectDecision: "reject-side-effect",
    clarifyExplicitTeaching: !0
  }),
  negationPolicy: Object.freeze({
    preserveNegatedCandidate: !0,
    rejectNegatedSideEffects: !0
  })
}), dn = /* @__PURE__ */ new Set(["Greeting", "Thanks", "Farewell"]), Gs = /* @__PURE__ */ new Set([
  "Greeting+Identity",
  "Greeting+RememberName",
  "Farewell+Thanks"
]), Ys = Object.freeze({
  "threshold-met": 0,
  "corroborated-producers": 1,
  "compatible-secondary-candidate": 2,
  "partial-candidate": 3,
  "missing-required-slot": 4,
  "insufficient-confidence": 5,
  "insufficient-margin": 6,
  "conflicting-candidates": 7,
  "compound-query": 8,
  "side-effect-evidence-insufficient": 9,
  "negation-conflict": 10,
  "no-viable-candidate": 11
}), Qs = Object.freeze({
  "confidence-threshold": 0,
  "candidate-margin": 1,
  "complete-slots": 2,
  "explicit-name": 3,
  "complete-triple": 4,
  "strong-non-alias-evidence": 5,
  "non-question-assertion": 6,
  "non-negated-assertion": 7
});
function mn(e, t) {
  return Object.freeze(
    [...new Set(e)].sort(
      (n, r) => t[n] - t[r] || n.localeCompare(r)
    )
  );
}
function q(e) {
  return mn(e, Ys);
}
function bn(e) {
  return mn(e, Qs);
}
function J(e) {
  return e.trim().replace(/\s+/gu, " ").toLocaleLowerCase("und");
}
function Hs(e) {
  return e.extraction.relations.some(
    ({ conceptId: t }) => t === "is-a"
  );
}
function Xe(e, t) {
  return Hs(e) && (t === "是" || t === "属于") ? "属于" : t;
}
function Nt(e, t, n) {
  const r = J(n);
  return Xe(e, t) === "属于" && r.startsWith("一种") && r.length > 2 ? r.slice(2) : r;
}
function Js(e, t) {
  const n = t.result;
  if (n === null)
    return `partial:${t.id}`;
  switch (n.type) {
    case "intent":
      return [
        "intent",
        n.intent,
        ...n.entities.map(J)
      ].join(":");
    case "statement":
      return [
        "statement",
        J(n.subject),
        Xe(e, n.relation),
        Nt(e, n.relation, n.object),
        n.negated
      ].join(":");
    case "query":
      return [
        "query",
        n.kind,
        J(n.subject),
        Xe(e, n.relation),
        n.object === void 0 ? "" : Nt(
          e,
          n.relation,
          n.object
        )
      ].join(":");
    case "unknown":
      return `unknown:${t.id}`;
  }
}
function Ze(e) {
  const t = new Set(
    e.entities.map(
      ({ kind: n, start: r, end: i, value: c }) => `${n}:${r}:${i}:${c}`
    )
  );
  return e.evidence.length + t.size;
}
function P(e) {
  var t, n;
  return ((t = e.result) == null ? void 0 : t.type) === "intent" && e.result.intent === "RememberName" ? "memory-write" : ((n = e.result) == null ? void 0 : n.type) === "statement" ? "knowledge-write" : e.sideEffect;
}
function te(e, t) {
  const n = P(e) === e.sideEffect ? 0 : 1, r = P(t) === t.sideEffect ? 0 : 1;
  return n - r || t.confidence - e.confidence || Ze(t) - Ze(e) || e.missingSlots.length - t.missingSlots.length || m.producerTieBreak[e.producer] - m.producerTieBreak[t.producer] || e.id.localeCompare(t.id);
}
function Xs(e, t) {
  const n = /* @__PURE__ */ new Map(), r = [...t].sort(te);
  for (const i of r) {
    const c = Js(e, i), s = n.get(c);
    s === void 0 ? n.set(c, [i]) : s.push(i);
  }
  return Object.freeze(
    [...n.entries()].map(([i, c]) => {
      const s = Object.freeze(
        [...c].sort(te)
      );
      return Object.freeze({
        key: i,
        representative: s[0],
        supporters: s
      });
    }).sort(
      (i, c) => te(
        i.representative,
        c.representative
      )
    )
  );
}
function Zs(e, t) {
  if (P(e) !== "none")
    return t.sideEffectAcceptThreshold;
  const n = e.result;
  return (n == null ? void 0 : n.type) === "intent" && dn.has(n.intent) ? t.passiveIntentAcceptThreshold : (n == null ? void 0 : n.type) === "query" || (n == null ? void 0 : n.type) === "intent" && (n.intent === "Identity" || n.intent === "RecallName") ? t.queryAcceptThreshold : t.partialCandidateThreshold;
}
function at(e) {
  var t;
  return ((t = e.result) == null ? void 0 : t.type) === "statement" && e.result.negated;
}
function ea(e) {
  var n;
  if (((n = e.result) == null ? void 0 : n.type) !== "intent" || e.result.intent !== "RememberName")
    return !1;
  const t = e.result.entities[0];
  return t === void 0 ? !1 : e.entities.some(
    (r) => r.kind === "person-name" && J(r.value) === J(t)
  );
}
function ta(e) {
  const t = e.result;
  return (t == null ? void 0 : t.type) === "statement" && t.subject.trim().length > 0 && t.relation.trim().length > 0 && t.object.trim().length > 0;
}
function na(e, t) {
  const n = /* @__PURE__ */ new Set([
    "legacy-regex",
    "relation-pattern",
    "entity-pattern",
    "teaching-cue"
  ]);
  return e.evidence.some(({ kind: i }) => n.has(i)) ? !0 : !(e.evidence.length > 0 && e.evidence.every(
    ({ kind: i, value: c }) => i === "lexicon-alias" && ((c == null ? void 0 : c.length) ?? 0) <= t.weakAliasMaximumLength
  )) && Ze(e) >= t.minimumSideEffectEvidenceUnits;
}
function gn(e, t, n) {
  var s;
  const r = P(e);
  if (r === "none")
    return Object.freeze({
      safe: !0,
      requiredEvidence: Object.freeze([]),
      reasonCodes: Object.freeze([])
    });
  const i = [], c = [];
  return (e.missingSlots.length > 0 || e.result === null) && (i.push("complete-slots"), c.push("missing-required-slot")), e.confidence < n.sideEffectAcceptThreshold && (i.push("confidence-threshold"), c.push("insufficient-confidence")), n.negationPolicy.rejectNegatedSideEffects && at(e) && (i.push("non-negated-assertion"), c.push("negation-conflict")), ((s = e.result) == null ? void 0 : s.type) === "statement" && t.extraction.questionCues.length > 0 && (i.push("non-question-assertion"), c.push("side-effect-evidence-insufficient")), r === "memory-write" && !ea(e) && (i.push("explicit-name"), c.push("side-effect-evidence-insufficient")), r === "knowledge-write" && !ta(e) && (i.push("complete-triple"), c.push("side-effect-evidence-insufficient")), na(e, n) || (i.push("strong-non-alias-evidence"), c.push("side-effect-evidence-insufficient")), Object.freeze({
    safe: i.length === 0,
    requiredEvidence: bn(i),
    reasonCodes: q(c)
  });
}
function ra(e) {
  return e.result !== null && e.result.type !== "unknown" && e.missingSlots.length === 0;
}
function ia(e, t, n) {
  return at(e) && !n.negationPolicy.preserveNegatedCandidate ? !1 : ra(e) && e.confidence >= Zs(e, n) && gn(e, t, n).safe;
}
function ca(e, t) {
  const n = e.candidates.filter(
    (r) => ia(r, e, t)
  );
  return Xs(e, n);
}
function Tt(e) {
  var t;
  return ((t = e.result) == null ? void 0 : t.type) === "intent" ? e.result.intent : null;
}
function At(e, t) {
  const n = Tt(e), r = Tt(t);
  if (n === null || r === null)
    return !1;
  const i = [n, r].sort().join("+");
  return Gs.has(i);
}
function hn(e) {
  const t = e.result;
  return (t == null ? void 0 : t.type) === "query" || (t == null ? void 0 : t.type) === "intent" && (t.intent === "Identity" || t.intent === "RecallName");
}
function sa(e) {
  var t;
  return P(e) !== "none" ? "high" : hn(e) ? "low" : ((t = e.result) == null ? void 0 : t.type) === "intent" && dn.has(e.result.intent) ? "none" : "medium";
}
function Pe(e, t) {
  return Object.freeze(
    e.slice(0, t.maximumAlternatives).map(({ representative: n }) => n)
  );
}
function aa(e) {
  return e.concepts.some(({ id: t }) => t === "remember-name") ? "uncertain-name" : e.concepts.some(({ id: t }) => t === "teaching") && e.missingSlots.length > 1 ? "uncertain-teaching" : e.missingSlots.includes("relation") ? "missing-relation" : e.missingSlots.includes("subject") ? "missing-subject" : e.missingSlots.includes("object") ? "missing-object" : "ambiguous-intent";
}
function oa(e) {
  return e.result === null && e.concepts.some(({ id: t }) => t === "teaching");
}
function ua(e, t) {
  if (t.missingSlotPolicy.partialDecision !== "clarify")
    return null;
  const n = e.candidates.filter(
    (i) => i.result === null || i.missingSlots.length > 0
  ).filter(
    (i) => P(i) === "none" && (i.confidence >= t.partialCandidateThreshold || t.missingSlotPolicy.clarifyExplicitTeaching && oa(i))
  ).sort(te), r = n[0];
  return r === void 0 ? null : Object.freeze({
    kind: "clarify",
    candidateOptions: Object.freeze(
      n.slice(0, t.maximumAlternatives)
    ),
    missingSlots: Object.freeze([...r.missingSlots]),
    clarificationKind: aa(r),
    reasonCodes: q([
      "partial-candidate",
      "missing-required-slot",
      ...r.confidence < t.partialCandidateThreshold ? ["insufficient-confidence"] : []
    ])
  });
}
function la(e, t) {
  const r = e.candidates.filter((i) => P(i) !== "none").filter(
    (i) => !at(i) || t.negationPolicy.preserveNegatedCandidate
  ).map(
    (i) => Object.freeze({
      candidate: i,
      assessment: gn(i, e, t)
    })
  ).filter(({ assessment: i }) => !i.safe).sort(
    (i, c) => te(i.candidate, c.candidate)
  )[0];
  return r === void 0 ? null : Object.freeze({
    kind: "reject-side-effect",
    rejectedCandidate: r.candidate,
    requiredEvidence: r.assessment.requiredEvidence,
    reasonCodes: r.assessment.reasonCodes
  });
}
function fa(e) {
  return Object.freeze({
    count: e.diagnostics.length,
    codes: Object.freeze(
      [...new Set(e.diagnostics.map(({ code: t }) => t))].sort()
    )
  });
}
function da(e, t = Vs) {
  const n = ca(e, t), r = n.filter(
    ({ representative: b }) => hn(b)
  );
  if (e.extraction.questionCues.length >= 2 && r.length >= 2)
    return Object.freeze({
      kind: "clarify",
      candidateOptions: Pe(r, t),
      missingSlots: Object.freeze([]),
      clarificationKind: "ambiguous-intent",
      reasonCodes: q([
        "compound-query",
        "conflicting-candidates"
      ])
    });
  const i = n[0];
  if (i === void 0) {
    const b = ua(e, t);
    if (b !== null)
      return b;
    const g = la(
      e,
      t
    );
    if (g !== null)
      return g;
    const S = e.candidates.some(
      (R) => R.result !== null && R.result.type !== "unknown"
    );
    return Object.freeze({
      kind: "no-understanding",
      diagnosticsSummary: fa(e),
      reasonCodes: q([
        ...S ? ["insufficient-confidence"] : [],
        "no-viable-candidate"
      ])
    });
  }
  const c = i.representative, s = n.slice(1).filter(
    ({ representative: b }) => At(c, b)
  ), a = n.slice(1).filter(
    ({ representative: b }) => !At(c, b)
  ), o = a[0];
  if (o !== void 0 && c.confidence - o.representative.confidence < t.minimumCandidateMargin)
    return P(c) !== "none" ? Object.freeze({
      kind: "reject-side-effect",
      rejectedCandidate: c,
      requiredEvidence: bn(["candidate-margin"]),
      reasonCodes: q([
        "insufficient-margin",
        "conflicting-candidates"
      ])
    }) : Object.freeze({
      kind: "clarify",
      candidateOptions: Pe(
        [i, o],
        t
      ),
      missingSlots: Object.freeze([]),
      clarificationKind: "conflicting-candidates",
      reasonCodes: q([
        "insufficient-margin",
        "conflicting-candidates"
      ])
    });
  const d = Object.freeze(
    s.slice(0, t.maximumAlternatives).map(({ representative: b }) => b)
  ), l = Pe(
    a,
    t
  );
  return Object.freeze({
    kind: "accept",
    selectedCandidate: c,
    secondaryCandidates: d,
    confidence: T(c.confidence),
    reasonCodes: q([
      "threshold-met",
      ...i.supporters.length > 1 ? ["corroborated-producers"] : [],
      ...d.length > 0 ? ["compatible-secondary-candidate"] : []
    ]),
    alternatives: l,
    riskLevel: sa(c)
  });
}
const ma = {
  identity: p.Is,
  capability: p.Can,
  creator: xt
};
function ba(e) {
  return e === "identity" || e === "capability" || e === "creator";
}
const ga = /* @__PURE__ */ new Set([
  "属于",
  "是",
  "会",
  "喜欢",
  "在",
  "有",
  "意思是",
  "开发者",
  "none",
  "unknown"
]);
function ge(e) {
  return e === void 0 || e.length === 0 ? "none" : ga.has(
    e
  ) ? e : "unknown";
}
function ha() {
  var e;
  try {
    const t = (e = globalThis.performance) == null ? void 0 : e.now();
    return typeof t == "number" && Number.isFinite(t) ? t : null;
  } catch {
    return null;
  }
}
function he(e, t) {
  return e === null || t === null || !Number.isFinite(e) || !Number.isFinite(t) || t < e ? null : t - e;
}
function pn(e) {
  switch (e.kind) {
    case "accept":
      return [
        e.selectedCandidate,
        ...e.secondaryCandidates
      ];
    case "clarify":
      return e.candidateOptions;
    case "reject-side-effect":
      return [e.rejectedCandidate];
    case "no-understanding":
      return [];
  }
}
function De(e, t, n) {
  return Object.freeze({
    negatedInput: e.extraction.negationCues.length > 0,
    contextResolved: n && pn(t).some(
      ({ producer: r }) => r === "context"
    )
  });
}
function pa(e) {
  switch (e) {
    case "missing-subject":
      return "missing-subject";
    case "missing-relation":
      return "missing-relation";
    case "missing-object":
      return "missing-object";
    case "ambiguous-intent":
      return "ambiguous-intent";
    case "conflicting-candidates":
      return "conflicting-candidates";
    case "uncertain-name":
    case "uncertain-teaching":
      return "insufficient-evidence";
    case "none":
      return "unclassified";
  }
}
function ja(e) {
  return {
    startedAt: e,
    resultCategory: "safe-fallback",
    reasonCategory: "unclassified",
    relationCategory: "none",
    semanticAdopted: !1,
    legacyFallback: !1,
    contextUsed: !1,
    clarificationKind: "none",
    reasonerPathLength: 0,
    semanticDurationMs: null,
    reasonerDurationMs: null,
    queriedRelation: "none",
    alternativeKnownRelation: "none",
    alignmentResult: "unavailable",
    classificationLocked: !1
  };
}
function ya(e, t) {
  const [n = G, r] = e.entities, i = ba(r) ? r : "identity", c = ma[i], s = t.match({ subject: n, relation: c });
  return { kind: "identity", aspect: i, subject: n, facts: s, raw: e.raw };
}
function Oa(e, t) {
  const [n] = e.entities, r = t.remember(ne.Name, n ?? "");
  return { kind: "remembered", key: r.key, value: r.value, raw: e.raw };
}
function Sa(e, t) {
  const n = t.recall(ne.Name);
  return { kind: "recalled", key: ne.Name, value: (n == null ? void 0 : n.value) ?? null, raw: e.raw };
}
function Ea(e, t, n) {
  switch (e.intent) {
    case "Greeting":
      return { kind: "greeting", raw: e.raw };
    case "Thanks":
      return { kind: "thanks", raw: e.raw };
    case "Farewell":
      return { kind: "farewell", raw: e.raw };
    case "Identity":
      return ya(e, t);
    case "RememberName":
      return Oa(e, n);
    case "RecallName":
      return Sa(e, n);
    default: {
      const r = e.intent;
      throw new Error(`createSunlandEngine: unhandled intent "${String(r)}"`);
    }
  }
}
function za(e = {}) {
  var ot, ut, lt, ft;
  const t = e.knowledgeStore ?? xn(), n = e.memory ?? Mn(), r = pi(e.personalityId), i = e.parser ?? Mt(), c = e.storage, s = e.semanticMode ?? "passive", a = e.semanticContextMode ?? "off", o = e.semanticDebug === !0, d = ((ot = e.semanticRuntime) == null ? void 0 : ot.analyze) ?? Es, l = ((ut = e.semanticRuntime) == null ? void 0 : ut.plan) ?? da, b = ((lt = e.observationRuntime) == null ? void 0 : lt.now) ?? ha, g = ((ft = e.observationRuntime) == null ? void 0 : ft.finalizeSummary) ?? ((f) => f);
  let S = null;
  const R = vn(), w = c ? `${c.key}::memory` : void 0;
  c && Nn(t, c.adapter, c.key), w && c && Kn(n, c.adapter, w), e.seedDemoData === !0 && t.all().length === 0 && zn(t);
  function B() {
    c && In(t, c.adapter, c.key);
  }
  function oe() {
    c && w && _n(n, c.adapter, w);
  }
  function A() {
    try {
      const f = b();
      return typeof f == "number" && Number.isFinite(f) ? f : null;
    } catch {
      return null;
    }
  }
  function ke(f, j) {
    if ((f.type === "query" || f.type === "statement") && (j.relationCategory = ge(
      f.relation
    )), f.type === "query" && (j.queriedRelation = ge(
      f.relation
    )), !j.classificationLocked) {
      if (f.type === "unknown") {
        j.resultCategory = "no-understanding", j.reasonCategory = "unknown-safe-fallback";
        return;
      }
      j.resultCategory = "understood", j.reasonCategory = j.semanticAdopted ? "complete-passive-understanding" : "unclassified";
    }
  }
  function ze(f, j, u) {
    if (f.semanticAdopted = s === "passive" && u.kind !== "fallback-legacy", f.legacyFallback = s === "shadow" || u.kind === "fallback-legacy", f.contextUsed = u.kind !== "fallback-legacy" && pn(j).some(
      ({ producer: y }) => y === "context"
    ), u.kind === "clarification") {
      f.clarificationKind = u.context.clarificationKind, u.context.clarificationKind === "missing-subject" && f.contextUsed ? (f.resultCategory = "context-unresolved", f.reasonCategory = "unresolved-context") : (f.resultCategory = "clarification", f.reasonCategory = pa(
        u.context.clarificationKind
      )), f.classificationLocked = !0;
      return;
    }
    u.kind === "no-understanding" && (u.failure.reason.startsWith(
      "legacy-side-effect-blocked:"
    ) || u.failure.reason.startsWith(
      "legacy-side-effect-rejected:"
    ) || u.failure.reason === "semantic-side-effect-rejected" ? (f.resultCategory = "side-effect-blocked", f.reasonCategory = "blocked-side-effect") : (f.resultCategory = "no-understanding", f.reasonCategory = "unknown-safe-fallback"), f.classificationLocked = !0);
  }
  function ue(f, j, u, y) {
    if (y.relationCategory = ge(
      f.relation
    ), y.queriedRelation = y.relationCategory, y.alternativeKnownRelation = u.mode === "fallback" && j.length > 0 ? ge(u.matchedRelation) : "none", j.length === 0) {
      y.reasonerPathLength = 0, y.classificationLocked || (y.resultCategory = "missing-knowledge", y.reasonCategory = "missing-knowledge"), y.alignmentResult = u.mode === "fallback" ? "no-alternative-known" : "unavailable";
      return;
    }
    y.reasonerPathLength = j.reduce(
      (F, U) => Math.max(F, Math.max(1, U.path.length - 1)),
      1
    ), y.alignmentResult = "aligned";
  }
  function v(f, j, u = {}) {
    switch (j !== void 0 && ke(f, j), f.type) {
      case "statement": {
        const y = t.add(
          { subject: f.subject, relation: f.relation, object: f.object, negated: f.negated },
          { source: "user" }
        );
        return B(), r.respond({ kind: "learned", record: y });
      }
      case "query": {
        const y = f.subject.trim().toLocaleLowerCase("und") === G.toLocaleLowerCase("und") ? R : t, F = j === void 0 ? null : A(), U = $i(
          f,
          y,
          u
        ), x = U.result;
        j !== void 0 && (j.reasonerDurationMs = he(
          F,
          A()
        ), ue(
          f,
          x.answers,
          U.relationResolution,
          j
        ));
        const le = jt.plan(x);
        return r.respond({ kind: "reasoning-result", result: x, plan: le });
      }
      case "intent": {
        const y = Ea(f, R, n);
        return f.intent === "RememberName" && oe(), r.respond(y);
      }
      case "unknown":
        return r.respond({ kind: "unknown-input", failure: f });
      default: {
        const y = f;
        throw new Error(`createSunlandEngine: unhandled parse result ${JSON.stringify(y)}`);
      }
    }
  }
  function Ie(f) {
    const j = jt.planClarification(f);
    return r.respond({ kind: "clarification", plan: j });
  }
  function k(f, j = {}) {
    const u = j.observationMode === "summary" ? ja(A()) : void 0, y = X(a === "enabled" ? j.semanticContext : j.semanticContext ?? Xt()), F = () => Object.freeze({
      kind: "none",
      baseVersion: y.version
    }), U = (C) => {
      if (u === void 0) return C;
      try {
        let ee = null;
        try {
          const Te = t.all().length;
          ee = Number.isSafeInteger(Te) && Te >= 0 ? Te : null;
        } catch {
          ee = null;
        }
        const Ne = {
          resultCategory: u.resultCategory,
          reasonCategory: u.reasonCategory,
          relationCategory: u.relationCategory,
          semanticAdopted: u.semanticAdopted,
          legacyFallback: u.legacyFallback,
          contextUsed: u.contextUsed,
          clarificationKind: u.clarificationKind,
          reasonerPathLength: u.reasonerPathLength,
          knowledgeCount: ee,
          totalDurationMs: he(
            u.startedAt,
            A()
          ),
          semanticDurationMs: u.semanticDurationMs,
          reasonerDurationMs: u.reasonerDurationMs,
          queriedRelation: u.queriedRelation,
          alternativeKnownRelation: u.alternativeKnownRelation,
          alignmentResult: u.alignmentResult
        }, V = Hi(Ne), fe = Xi(
          g(V)
        );
        return fe === null ? C : Object.freeze({
          response: C.response,
          semanticContextUpdate: C.semanticContextUpdate,
          observationSummary: fe
        });
      } catch {
        return C;
      }
    }, x = (C) => U(
      Object.freeze({
        response: C,
        semanticContextUpdate: F()
      })
    ), le = (C, ee, Ne) => {
      let V = a === "enabled";
      if (V && j.canCommitSemanticContext !== void 0)
        try {
          V = j.canCommitSemanticContext();
        } catch {
          V = !1;
        }
      const fe = s === "passive" ? xc({
        context: y,
        decision: ee,
        executedResult: Ne,
        turnId: j.turnId ?? `turn-${y.version + 1}`,
        canCommit: V
      }) : F();
      return U(
        Object.freeze({ response: C, semanticContextUpdate: fe })
      );
    }, _ = i.parse(f);
    if (S = null, s === "off")
      return u !== void 0 && (u.legacyFallback = !0), x(
        v(_, u)
      );
    let W, $, I;
    const dt = u === void 0 ? null : A();
    try {
      W = d(
        f,
        a === "enabled" ? y : void 0
      ), $ = l(
        W,
        e.understandingPolicy
      ), I = Ms(
        $,
        _,
        W
      ), u !== void 0 && (u.semanticDurationMs = he(
        dt,
        A()
      ), ze(
        u,
        $,
        I
      )), o && (S = Fs(
        s,
        _,
        $,
        I
      ));
    } catch {
      u !== void 0 && (u.semanticDurationMs = he(
        dt,
        A()
      ), u.semanticAdopted = !1, u.legacyFallback = !0), o && (S = Ws(
        s,
        _
      ));
      const C = an(_) ? v({
        type: "unknown",
        raw: _.raw,
        reason: "semantic-side-effect-validation-unavailable"
      }, u) : v(_, u, {
        negatedInput: !0
      });
      return u !== void 0 && (u.resultCategory = "safe-fallback", u.reasonCategory = "semantic-runtime", u.classificationLocked = !0), x(C);
    }
    if (s === "shadow")
      return x(
        v(
          _,
          u,
          De(
            W,
            $,
            !1
          )
        )
      );
    switch (I.kind) {
      case "adopt":
        return le(
          v(
            I.result,
            u,
            De(
              W,
              $,
              !0
            )
          ),
          $,
          I.result
        );
      case "clarification":
        return x(
          Ie(I.context)
        );
      case "no-understanding":
        return x(
          v(I.failure, u)
        );
      case "fallback-legacy":
        return le(
          v(
            I.result,
            u,
            De(
              W,
              $,
              !1
            )
          ),
          $,
          I.result
        );
      default: {
        const C = I;
        throw new Error(
          `createSunlandEngine: unhandled semantic adaptation ${JSON.stringify(C)}`
        );
      }
    }
  }
  return {
    knowledgeStore: t,
    memory: n,
    semanticMode: s,
    semanticContextMode: a,
    getLastSemanticShadow() {
      return o ? S : null;
    },
    respond(f) {
      return k(f).response;
    },
    process: k
  };
}
function Ia() {
  const e = /* @__PURE__ */ new Map();
  return {
    getItem(t) {
      return e.get(t) ?? null;
    },
    setItem(t, n) {
      e.set(t, n);
    },
    removeItem(t) {
      e.delete(t);
    }
  };
}
export {
  Ft as CONTEXT_SCHEMA_VERSION,
  xt as CREATOR_RELATION,
  gi as DEFAULT_PERSONALITY_ID,
  Ui as DURATION_BUCKETS,
  Wn as FAREWELL_PHRASES,
  Tn as FROST_SUBJECT,
  Fe as FrostPersonality,
  Un as GREETING_PHRASES,
  vt as InMemoryKnowledgeStore,
  qi as KNOWLEDGE_COUNT_BUCKETS,
  Ue as LEGACY_SIDE_EFFECT_LIMITS,
  Di as OBSERVATION_CLARIFICATION_KINDS,
  Mi as OBSERVATION_REASON_CATEGORIES,
  Pi as OBSERVATION_RELATION_CATEGORIES,
  Ki as OBSERVATION_RESULT_CATEGORIES,
  Wt as OBSERVATION_SCHEMA_VERSION,
  pt as PlainPersonality,
  Bi as REASONER_PATH_BUCKETS,
  er as RECALL_NAME_PHRASES,
  Fi as RELATION_ALIGNMENT_RESULTS,
  Tr as RegexParser,
  Bt as SEMANTIC_SCHEMA_VERSION,
  qt as SUNLAND_CORE_VERSION,
  G as SUNLAND_SUBJECT,
  Bn as THANKS_PHRASES,
  ka as applySemanticContextUpdate,
  $e as bucketDuration,
  Li as bucketKnowledgeCount,
  _i as bucketReasonerPath,
  Kt as countKnownRelationMentions,
  Xt as createEmptySemanticContext,
  Vn as createFarewellIntentMatcher,
  qn as createGreetingIntentMatcher,
  Zn as createIdentityIntentMatcher,
  Se as createKeywordIntentMatcher,
  xn as createKnowledgeStore,
  kr as createLocatePattern,
  Ia as createMemoryStorageAdapter,
  Er as createObjectOfPattern,
  Hi as createObservationSummary,
  Mt as createParser,
  tr as createRecallNameIntentMatcher,
  hr as createRememberNameIntentMatcher,
  vn as createSelfKnowledgeStore,
  Be as createStatementPattern,
  za as createSunlandEngine,
  Fn as createThanksIntentMatcher,
  Cr as createVerifyPattern,
  zr as createWhyPattern,
  pr as defaultIntentMatchers,
  Nr as defaultPatterns,
  pi as getPersonality,
  Lt as hasChoiceOrSequenceStructure,
  _t as hasExplicitSideEffectProhibition,
  or as hasInternalClauseBoundary,
  ur as hasQuestionStructure,
  et as hasUnsafeLegacySideEffectStructure,
  Ra as listPersonalities,
  Nn as loadKnowledgeStore,
  qe as normalizeCapturedValue,
  Or as normalizeInput,
  X as normalizeSemanticContext,
  Ca as registerPersonality,
  Xi as sanitizeObservationSummary,
  In as saveKnowledgeStore,
  zn as seedKnowledgeStore,
  kn as seedTriples,
  An as selfKnowledgeTriples,
  $t as stripTrailingDeclarativePunctuation,
  Ji as validateObservationSummary
};
