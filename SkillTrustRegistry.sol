// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SkillTrust Registry v2 — ระบบออกและตรวจสอบใบรับรองดิจิทัล
/// @author พบพร จิตโสภา 66016519
/// @dev Deployed on Sepolia: 0x94e2fEb4918E018eF0539e425057075Eb05537BD
/// @notice บันทึกเฉพาะ hash ของไฟล์ใบรับรองบน blockchain (ชื่อผู้รับอยู่ในไฟล์ ไม่อยู่บน chain)
///         รองรับ: วันหมดอายุ, ระดับผลการอบรม, ออกหลายใบพร้อมกัน, ระงับชั่วคราว/คืนสถานะ/เพิกถอน
///         ประวัติทุกการเปลี่ยนสถานะถูกบันทึกเป็น event บน blockchain (ลบไม่ได้)
contract SkillTrustRegistry {
    // ───────────── Errors ─────────────
    error NotAdmin();
    error NotIssuer();
    error InvalidInput();
    error CourseExists();
    error CourseNotFound();
    error CourseClosed();
    error CertExists();
    error CertNotFound();
    error HashUsed();
    error BadStatus();

    // ───────────── Types ─────────────
    enum Grade { Pass, Merit, Distinction }
    enum Status { Active, Suspended, Revoked }
    enum Action { Issued, Suspended, Reinstated, Revoked }
    /// ผลการตรวจสอบ: 0 ไม่พบ, 1 ใช้งานได้, 2 หมดอายุ, 3 ระงับชั่วคราว, 4 เพิกถอน
    enum Verdict { NotFound, Valid, Expired, Suspended, Revoked }

    struct Course {
        string code;
        string name;
        string category;     // AI / Cybersecurity / Cloud / Data ...
        uint32 hoursCount;   // จำนวนชั่วโมงอบรม
        uint32 validityDays; // อายุใบรับรอง (0 = ไม่หมดอายุ)
        bool active;         // เปิดให้ออกใบรับรองหรือไม่
        uint64 createdAt;
        bool exists;
    }

    struct Certificate {
        string courseCode;
        address recipient;
        bytes32 fileHash;    // keccak256 ของไฟล์ใบรับรอง
        Grade grade;
        Status status;
        uint64 issuedAt;
        uint64 expiresAt;    // 0 = ไม่หมดอายุ
        address issuedBy;
        bool exists;
    }

    struct BatchItem {
        string certId;
        address recipient;
        bytes32 fileHash;
        Grade grade;
    }

    // ───────────── Storage ─────────────
    address public admin;
    mapping(address => bool) public isIssuer;

    mapping(string => Course) private courses;
    string[] private courseCodes;

    mapping(string => Certificate) private certs;
    mapping(address => string[]) private certsOf;
    mapping(bytes32 => string) public certIdByHash;
    uint256 public totalCertificates;

    // ───────────── Events ─────────────
    event IssuerSet(address indexed account, bool allowed);
    event CourseCreated(string code, string name);
    event CourseStatusChanged(string code, bool active);
    event CertificateIssued(string certId, string courseCode, address indexed recipient, bytes32 fileHash);
    event StatusChanged(string certId, Action action, string note, address indexed by);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier onlyIssuer() {
        if (msg.sender != admin && !isIssuer[msg.sender]) revert NotIssuer();
        _;
    }

    constructor() {
        admin = msg.sender;
        isIssuer[msg.sender] = true;
        emit IssuerSet(msg.sender, true);
    }

    // ───────────── Admin ─────────────
    function setIssuer(address account, bool allowed) external onlyAdmin {
        if (account == address(0)) revert InvalidInput();
        isIssuer[account] = allowed;
        emit IssuerSet(account, allowed);
    }

    /// 1. ลงทะเบียนหลักสูตร
    function createCourse(
        string calldata code,
        string calldata name,
        string calldata category,
        uint32 hoursCount,
        uint32 validityDays
    ) external onlyAdmin {
        if (bytes(code).length == 0 || bytes(name).length == 0) revert InvalidInput();
        if (courses[code].exists) revert CourseExists();
        courses[code] = Course(code, name, category, hoursCount, validityDays, true, uint64(block.timestamp), true);
        courseCodes.push(code);
        emit CourseCreated(code, name);
    }

    function setCourseActive(string calldata code, bool active) external onlyAdmin {
        if (!courses[code].exists) revert CourseNotFound();
        courses[code].active = active;
        emit CourseStatusChanged(code, active);
    }

    // ───────────── Issue (2 + 3) ─────────────
    /// ออกใบรับรอง 1 ใบ และบันทึก hash ของไฟล์
    /// @param expiresAt 0 = ใช้อายุตามหลักสูตร, หรือกำหนด timestamp เอง (ต้องอยู่ในอนาคต)
    function issueCertificate(
        string calldata certId,
        string calldata courseCode,
        address recipient,
        bytes32 fileHash,
        Grade grade,
        uint64 expiresAt
    ) external onlyIssuer {
        Course storage c = _openCourse(courseCode);
        _issue(certId, c, recipient, fileHash, grade, _expiry(c, expiresAt));
    }

    /// ออกใบรับรองหลายใบพร้อมกัน (หลักสูตรเดียวกัน) สูงสุด 20 ใบต่อครั้ง
    function issueBatch(string calldata courseCode, BatchItem[] calldata items, uint64 expiresAt) external onlyIssuer {
        uint256 n = items.length;
        if (n == 0 || n > 20) revert InvalidInput();
        Course storage c = _openCourse(courseCode);
        uint64 exp = _expiry(c, expiresAt);
        for (uint256 i = 0; i < n; i++) {
            _issue(items[i].certId, c, items[i].recipient, items[i].fileHash, items[i].grade, exp);
        }
    }

    // ───────────── Status (5) ─────────────
    /// ระงับชั่วคราว (คืนสถานะได้)
    function suspendCertificate(string calldata certId, string calldata reason) external onlyIssuer {
        Certificate storage c = _cert(certId);
        if (c.status != Status.Active) revert BadStatus();
        c.status = Status.Suspended;
        _log(certId, Action.Suspended, reason);
    }

    /// คืนสถานะใบที่ถูกระงับ
    function reinstateCertificate(string calldata certId, string calldata note) external onlyIssuer {
        Certificate storage c = _cert(certId);
        if (c.status != Status.Suspended) revert BadStatus();
        c.status = Status.Active;
        _log(certId, Action.Reinstated, note);
    }

    /// เพิกถอนถาวร (ประวัติการออกยังอยู่)
    function revokeCertificate(string calldata certId, string calldata reason) external onlyIssuer {
        Certificate storage c = _cert(certId);
        if (c.status == Status.Revoked) revert BadStatus();
        c.status = Status.Revoked;
        _log(certId, Action.Revoked, reason);
    }

    // ───────────── Views (4 + 6) ─────────────
    /// 4. ตรวจสอบสถานะใบรับรอง
    function verify(string calldata certId) external view returns (Verdict) {
        return _verdict(certs[certId]);
    }

    /// ตรวจจากไฟล์: ส่ง hash ของไฟล์มา จะได้รหัสใบรับรองและผลตรวจ
    function verifyByHash(bytes32 fileHash) external view returns (string memory certId, Verdict verdict) {
        certId = certIdByHash[fileHash];
        verdict = bytes(certId).length == 0 ? Verdict.NotFound : _verdict(certs[certId]);
    }

    function _verdict(Certificate storage c) private view returns (Verdict) {
        if (!c.exists) return Verdict.NotFound;
        if (c.status == Status.Revoked) return Verdict.Revoked;
        if (c.status == Status.Suspended) return Verdict.Suspended;
        if (c.expiresAt != 0 && block.timestamp > c.expiresAt) return Verdict.Expired;
        return Verdict.Valid;
    }

    function getCertificate(string calldata certId) external view returns (Certificate memory) {
        if (!certs[certId].exists) revert CertNotFound();
        return certs[certId];
    }

    function getCourse(string calldata code) external view returns (Course memory) {
        if (!courses[code].exists) revert CourseNotFound();
        return courses[code];
    }

    function getCourseCodes() external view returns (string[] memory) {
        return courseCodes;
    }

    /// 6. ใบรับรองที่ผูกกับ wallet
    function getCertificatesOf(address recipient) external view returns (string[] memory) {
        return certsOf[recipient];
    }

    // ───────────── Internal ─────────────
    function _openCourse(string calldata code) private view returns (Course storage c) {
        c = courses[code];
        if (!c.exists) revert CourseNotFound();
        if (!c.active) revert CourseClosed();
    }

    function _expiry(Course storage c, uint64 custom) private view returns (uint64) {
        if (custom != 0) {
            if (custom <= block.timestamp) revert InvalidInput();
            return custom;
        }
        return c.validityDays == 0 ? 0 : uint64(block.timestamp + uint256(c.validityDays) * 1 days);
    }

    function _issue(
        string calldata certId,
        Course storage course,
        address recipient,
        bytes32 fileHash,
        Grade grade,
        uint64 expiresAt
    ) private {
        if (bytes(certId).length == 0 || recipient == address(0) || fileHash == bytes32(0)) revert InvalidInput();
        Certificate storage c = certs[certId];
        if (c.exists) revert CertExists();
        if (bytes(certIdByHash[fileHash]).length != 0) revert HashUsed();
        c.courseCode = course.code;
        c.recipient = recipient;
        c.fileHash = fileHash;
        c.grade = grade;
        c.issuedAt = uint64(block.timestamp);
        c.expiresAt = expiresAt;
        c.issuedBy = msg.sender;
        c.exists = true;
        certsOf[recipient].push(certId);
        certIdByHash[fileHash] = certId;
        totalCertificates++;
        emit CertificateIssued(certId, course.code, recipient, fileHash);
        _log(certId, Action.Issued, "");
    }

    function _cert(string calldata certId) private view returns (Certificate storage c) {
        c = certs[certId];
        if (!c.exists) revert CertNotFound();
    }

    function _log(string calldata certId, Action action, string memory note) private {
        emit StatusChanged(certId, action, note, msg.sender);
    }
}
