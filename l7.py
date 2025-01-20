import requests
from bs4 import BeautifulSoup
import html
from datetime import datetime

def GetUniqueEmail():
    # Get the current date and time
    now = datetime.now()

    # Format the date and time as MMDDHHSS
    current_time = now.strftime("%m%d%H%S")
    # Create the string with "mammotty_" prepended and "@gmail.com" appended
    email = f"mammotty_{current_time}@gmail.com"

    print("Generated Email:", email)

    return email


def getCSRFTokenForLayerseven():
    # URL to send the request to
    url = "https://panel.layerseven.ai/sign-in"

    # Send a GET request to the URL
    response = requests.get(url)

    # Check if the response has cookies and extract the csrftoken
    csrftoken = response.cookies.get("csrftoken")

    # Print the extracted csrftoken
    if csrftoken:
        # print("csrftoken:", csrftoken)
        return csrftoken
    else:
        print("No csrftoken found in the response cookies.")
        return None


def getnewDuckAddress():
    # URL to send the request to
    url = "https://quack.duckduckgo.com/api/email/addresses"

    # Send the POST request
    response = requests.post(url, headers=headers)
    # Check if the response is valid
    if response.status_code == 201:
        response_json = response.json()
        address = response_json.get("address")
        if address:
            modified_address = f"{address}@duck.com"
            print("Modified Address:", modified_address)
            return modified_address
        else:
            print("'address' key not found in the response JSON.")
            return None
    else:
        print("Request failed with status code:", response.status_code)
        return None

def getMiddlewareToken(csrftoken,email):
    print("csrftoken passed to getMiddlewareToken: " + csrftoken)
    # URL to send the request to
    url = "https://panel.layerseven.ai/sign-up"
    headers = {
        "Cookie": "csrftoken="+ csrftoken+"; sessionid=""; email="+email+"; picture=None",
    }

    # Send a GET request to the URL
    response = requests.get(url, headers=headers)

    # Parse the HTML content
    soup = BeautifulSoup(response.text, 'html.parser')

    # Find the input field with name 'csrfmiddlewaretoken'
    csrf_token = soup.find('input', {'name': 'csrfmiddlewaretoken'})

    # Extract the value attribute
    if csrf_token and 'value' in csrf_token.attrs:
        print("csrfmiddlewaretoken:", csrf_token['value'])
        return csrf_token['value']
    else:
        print("csrfmiddlewaretoken not found.")
        return None


def signupForLayerseven(csrftoken, email):
    # URL to send the request to
    url = "https://panel.layerseven.ai/v1/sign-up/"
    headers = {
        "Cookie": "csrftoken="+ csrftoken+"; sessionid=""; email="+email+"; picture=None",
        "Content-Type": "application/x-www-form-urlencoded"
    }
    mwToken = getMiddlewareToken(csrftoken, email)
    print("=-------mwToken------=")
    print(mwToken)

    # duckAddress = getnewDuckAddress()
    duckAddress = email
    body = f"csrfmiddlewaretoken={mwToken}&email={duckAddress}&password=Lg6*%26bdHsKEC%23f5G"
    print("---------------")
    print (body)
    # Send a GET request to the URL
    response = requests.post(url, headers=headers, data=body, allow_redirects=False)
    # print(response.status_code)
    cookies = response.cookies
    for cookie in cookies:
        if (cookie.name == "session_id"):
            print(cookie.name, cookie.value)
            return cookie.value
    # print(response.status_code)
    #
    # # Check the response status and headers
    # print('Status Code:', response.status_code)
    # print('Location Header:', response.headers.get('Location'))


def checkoutLayerseven(csrftoken, session_id, email):
    # URL to send the request to
    url = "https://panel.layerseven.ai/checkout?free-trial=1"
    cookies = {
        'csrftoken': csrftoken, 'session_id': session_id, 'email': email, 'picture': 'None'
    }
    print("$$$$$$$$$$$$$$$")
    print(cookies)
    print("$$$$$$$$$$$$$$$")
    # Send a GET request to the URL
    response = requests.get(url, cookies=cookies, allow_redirects=True)
    print(response.status_code)
    cookies = response.cookies
    for cookie in cookies:
        print(cookie.name, cookie.value)
    print(response.status_code)
    html_content = response.text
    print(html_content)
    # Parse the HTML content using BeautifulSoup
    soup = BeautifulSoup(html_content, "html.parser")

    # Find the table with the specific class
    table = soup.find("table", class_="min-w-full divide-y divide-gray-300")

    # Extract the required string from the table
    required_url = None
    if table:
        required_url = table.find(string=lambda text: "http://cf.shark-cdn.me/get.php" in text)

    # Print the extracted URL
    if required_url:
        print("Extracted URL:", required_url)
    else:
        print("No matching URL found in the table.")

    #
    # # Check the response status and headers
    # print('Status Code:', response.status_code)
    # print('Location Header:', response.headers.get('Location'))


if __name__ == "__main__":
    # url = 'http://www.s.nickmom.com'
    # result = ur.isURLReachable(url)
    # print('A: %s | %s | %s | %s' % (url, result[0], result[1], result[2]))
    # getMiddlewareToken()
    email = GetUniqueEmail()
    csrftoken = getCSRFTokenForLayerseven()
    session_id=signupForLayerseven(csrftoken, email)
    checkoutLayerseven(csrftoken, session_id, email)
