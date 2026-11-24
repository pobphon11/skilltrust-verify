# SkillTrust Verify

**Blockchain Digital Certificate Verification System** (โจทย์ที่ 3)

ระบบออกและตรวจสอบใบรับรองดิจิทัลของ SkillTrust Academy บน Ethereum Smart Contract
ป้องกันการปลอมแปลงหรือแก้ไขไฟล์ใบรับรอง และให้ผู้ว่าจ้างตรวจสอบคุณวุฒิได้ทันที

🔗 **เว็บ DApp:** https://pobphon11.github.io/skilltrust-verify/

**ผู้จัดทำ:** พบพร จิตโสภา · รหัสนักศึกษา 66016519

---

## ฟังก์ชันตามโจทย์

| # | ฟังก์ชัน | วิธีที่ระบบทำ |
|---|---|---|
| 1 | ลงทะเบียนหลักสูตร (Create Training Course) | Admin สร้างหลักสูตร พร้อมรหัส ชื่อ หมวด จำนวนชั่วโมง และอายุของใบรับรอง และเปิด/ปิดการออกใบรับรองได้ |
| 2 | ออกใบรับรอง (Issue Certificate) | Issuer ออกใบรับรองพร้อมรหัสอ้างอิง วันที่ออก วันหมดอายุ ระดับผล (Pass/Merit/Distinction) และ Wallet ผู้รับ ออกทีละใบหรือหลายใบ (Batch สูงสุด 20 ใบ) ได้ |
| 3 | บันทึกหลักฐานบน Blockchain (Store Certificate Hash) | ระบบสร้างไฟล์ใบรับรอง (PNG) แล้วบันทึก `keccak256` ของไฟล์ไว้บน chain ถ้าไฟล์ถูกแก้แม้แต่จุดเดียว hash จะไม่ตรง |
| 4 | ตรวจสอบความถูกต้อง (Verify Certificate) | ค้นหาด้วยรหัส สแกน QR หรือลากไฟล์มาวาง ผลตรวจมี 5 แบบ: VALID / EXPIRED / SUSPENDED / REVOKED / NOT FOUND (และ TAMPERED เมื่อไฟล์ถูกแก้) |
| 5 | เพิกถอนใบรับรอง (Revoke Certificate) | ระงับชั่วคราว (Suspend) แล้วคืนสถานะได้ หรือเพิกถอนถาวร (Revoke) โดยประวัติการออกยังอยู่ครบ ทุกการเปลี่ยนแปลงแสดงเป็นไทม์ไลน์ |
| 6 | แสดงประวัติใบรับรอง (Certificate Dashboard) | ผู้เข้าอบรมเชื่อม Wallet เพื่อดูใบรับรองทั้งหมดพร้อมสถิติ และคัดลอกลิงก์ตรวจสอบส่งให้ผู้ว่าจ้าง |

## กฎทางธุรกิจ

- **รหัสใบรับรองไม่ซ้ำ:** contract ปฏิเสธรหัสซ้ำ (`CertExists`) และไฟล์ซ้ำ (`HashUsed`)
- **เฉพาะผู้ได้รับอนุญาต:** มี 3 บทบาท คือ Admin / Issuer / Verifier ผู้ไม่มีสิทธิ์ออกหรือเพิกถอนไม่ได้ (`NotAdmin`, `NotIssuer`)
- **ไม่นำข้อมูลส่วนบุคคลขึ้น Public Blockchain:** ชื่อผู้รับอยู่ในไฟล์ใบรับรองเท่านั้น บน chain เก็บเฉพาะ hash ของไฟล์

## ข้อมูลทางเทคนิค

| รายการ | ค่า |
|---|---|
| Network | Ethereum Sepolia Testnet |
| Smart Contract | [`0x94e2fEb4918E018eF0539e425057075Eb05537BD`](https://sepolia.etherscan.io/address/0x94e2fEb4918E018eF0539e425057075Eb05537BD) |
| Source code | [`SkillTrustRegistry.sol`](SkillTrustRegistry.sol) (Solidity ^0.8.20) |
| Frontend | HTML + JavaScript, ethers.js v6, MetaMask, qrcode.js, JSZip, html5-qrcode |

## วิธีใช้งาน

1. เปิดเว็บ แล้วกด **Connect Wallet** (MetaMask บน Sepolia)
2. **หลักสูตร:** Admin ลงทะเบียนหลักสูตร
3. **ออกใบรับรอง:** กรอกชื่อและ Wallet ผู้รับ ดูตัวอย่างใบรับรองแบบสด แล้วกดออก ระบบจะดาวน์โหลดไฟล์ PNG ต้นฉบับให้
4. **ตรวจสอบ:** ใส่รหัส สแกน QR หรือลากไฟล์ PNG มาวาง
5. **สถานะ / เพิกถอน:** ระงับ คืนสถานะ หรือเพิกถอน พร้อมระบุเหตุผล
