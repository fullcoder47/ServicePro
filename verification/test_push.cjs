const ts=require('typescript'),fs=require('fs'),assert=require('assert/strict');
if (!process.env.SERVICEPRO_PROJECT) throw new Error('Set SERVICEPRO_PROJECT');
const source=fs.readFileSync(process.env.SERVICEPRO_PROJECT+'/supabase/functions/_shared/push_policy.ts','utf8');
const code=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText;
const mod={exports:{}};new Function('exports','module',code)(mod.exports,mod);
const f=mod.exports.classifyFcm;
for(const [status,body,expected] of [[200,{},'success'],[404,{error:{details:[{errorCode:'UNREGISTERED'}]}},'unregistered'],[429,{},'retry'],[500,{},'retry'],[401,{},'retry'],[400,{error:{details:[{errorCode:'INVALID_ARGUMENT'}]}},'retry']])assert.equal(f(status,body),expected);
console.log('6 push policy checks passed');
